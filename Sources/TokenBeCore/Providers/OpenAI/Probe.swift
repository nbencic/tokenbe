import Foundation

/// 02 § openai Probe, the four steps of onboarding's "Test connection":
/// 1. `projects?limit=100` proves admin scope; 2. each project's `api_keys?limit=100` lists the keys;
/// 3. `usage/completions?…&limit=1` proves usage scope; 4. `costs?…&limit=1` proves cost scope.
///
/// Step 1 failing fails the probe with 02's message. A 401/403 on steps 2–4 turns that step's capability off, keeps
/// the redacted body, and the probe still passes (Q-029). Any other failure (offline, 429, 5xx, a body TokenBe
/// cannot read) fails the probe with its message. The probe never retries: onboarding shows the message at once.
extension OpenAIAdapter {
  public func probe(key: String, transport: any HTTPTransport) async -> ProbeResult {
    let redactor = log.redactor
    redactor.register(secret: key)
    defer { redactor.unregister(secret: key) }
    var probe = OpenAIProbe(adapter: self, key: key, transport: transport, now: Date())
    return await probe.run()
  }
}

/// How one probe step ended.
enum OpenAIProbeStep {
  case passed(Data)
  /// 401/403: the step's capability is off.
  case refused(status: Int)
  /// Ends the probe with this message.
  case failed(String)
}

/// One probe's state; a value type so the steps read top to bottom.
struct OpenAIProbe {
  let adapter: OpenAIAdapter
  let key: String
  let transport: any HTTPTransport
  let now: Date
  var capabilities = OpenAIAdapter.capabilities
  var bodies: [String: String] = [:]
  var keys: [DiscoveredKey] = []

  static let organization = OpenAIAdapter.organization
  static let name = ProviderID.openai.displayName

  mutating func run() async -> ProbeResult {
    // 1. Admin scope.
    let projects: OpenAIProjectList
    switch await step("projects", "\(Self.organization)/projects", [.init(name: "limit", value: "100")]) {
    case .passed(let body):
      guard let list = decoded(OpenAIProjectList.self, body, "projects") else { return failure(Self.unreadable) }
      projects = list
    case .refused(let status):
      return failure(status == 401 ? CoreStrings.OpenAI.notAdminKey : CoreStrings.OpenAI.missingScope)
    case .failed(let message):
      return failure(message)
    }
    // 2. Keys of every project.
    if let message = await listKeys(projects) { return failure(message) }
    // 3. Usage scope.
    let usageQuery: [URLQueryItem] = [
      .init(name: "start_time", value: String(OpenAIAdapter.floor(now.addingTimeInterval(-3600), to: 1))),
      .init(name: "bucket_width", value: "1h"), .init(name: "limit", value: "1")
    ]
    if let message = await scope("usage_completions", "\(Self.organization)/usage/completions", usageQuery, off: {
      $0.usage = false
      $0.perKeyUsage = false
    }) { return failure(message) }
    // 4. Cost scope.
    let costQuery: [URLQueryItem] = [
      .init(name: "start_time", value: String(OpenAIAdapter.floor(now.addingTimeInterval(-86400), to: 1))),
      .init(name: "limit", value: "1")
    ]
    if let message = await scope("costs", "\(Self.organization)/costs", costQuery, off: { $0.cost = false }) {
      return failure(message)
    }
    return ProbeResult(capabilities: capabilities, discoveredKeys: keys, currency: capabilities.currencyHint,
                       rawBodiesRedacted: bodies)
  }

  /// Steps 3 and 4: a refusal turns the scope's capabilities `off`; returns a message when the probe must end.
  mutating func scope(_ endpoint: String, _ path: String, _ query: [URLQueryItem],
                      off: (inout Capabilities) -> Void) async -> String? {
    switch await step(endpoint, path, query) {
    case .passed: return nil
    case .refused:
      off(&capabilities)
      return nil
    case .failed(let message): return message
    }
  }

  /// Step 2; returns a message when the probe must end.
  mutating func listKeys(_ projects: OpenAIProjectList) async -> String? {
    for project in projects.data {
      let path = OpenAIAdapter.apiKeysPath(project: project.id)
      switch await step("api_keys", path, [.init(name: "limit", value: "100")]) {
      case .passed(let body):
        guard let list = decoded(OpenAIAPIKeyList.self, body, "api_keys") else { return Self.unreadable }
        keys += list.data.map {
          DiscoveredKey(providerKeyID: $0.id, name: $0.name, redacted: $0.redactedValue, projectID: project.id)
        }
      case .refused:
        capabilities.keyNames = false
      case .failed(let message):
        return message
      }
    }
    return nil
  }

  static var unreadable: String { CoreStrings.unexpectedResponse(name) }

  mutating func step(_ endpoint: String, _ path: String, _ query: [URLQueryItem]) async -> OpenAIProbeStep {
    let redactor = adapter.log.redactor
    do {
      let response = try await OpenAIAdapter.send(path, query: query, key: key, transport: transport)
      bodies[endpoint] = RawBody.redacted(response.body, redactor: redactor)
      return .passed(response.body)
    } catch {
      switch error {
      case .auth(let status, let body):
        bodies[endpoint] = RawBody.truncated(redactor.redact(body))
        return .refused(status: status)
      case .server(_, let body):
        bodies[endpoint] = RawBody.truncated(redactor.redact(body))
      case .transport, .rateLimited, .decode, .schemaDrift, .providerRule, .cancelled:
        break
      }
      adapter.log.emit(.error, .pollFailed, cat: .poll(ProviderID.openai.rawValue), msg: "probe step failed",
                       acct: ProviderID.openai.rawValue, job: "probe", err: error,
                       ctx: ["endpoint": .string(endpoint), "attempts": 1])
      return .failed(Self.message(for: error))
    }
  }

  /// The human message for a failure that ends the probe (CoreStrings, Q-029). A 401/403 never gets here: `step`
  /// returns `.refused` for it.
  static func message(for error: PollError) -> String {
    error.humanMessage(provider: .openai)
  }

  func decoded<Value: Decodable>(_ type: Value.Type, _ body: Data, _ endpoint: String) -> Value? {
    do {
      let result = try LenientDecoding.decode(type, from: body, endpoint: endpoint)
      adapter.logUnknown(result, job: .keys, now: now)
      return result.value
    } catch {
      var missing = "\(error)"
      if case .decode(let field, let path) = error { missing = "\(field) (\(path))" }
      adapter.log.emit(.error, .pollSchemaDrift, cat: .poll(ProviderID.openai.rawValue),
                       msg: "probe response could not be decoded", acct: ProviderID.openai.rawValue, job: "probe",
                       err: error, ctx: [
                         "missing_keys": .string(missing), "sample": .string(String(bodies[endpoint]?.prefix(512) ?? ""))
                       ])
      return nil
    }
  }

  func failure(_ message: String) -> ProbeResult {
    ProbeResult(capabilities: capabilities, humanMessage: message, discoveredKeys: keys,
                currency: capabilities.currencyHint, rawBodiesRedacted: bodies)
  }
}
