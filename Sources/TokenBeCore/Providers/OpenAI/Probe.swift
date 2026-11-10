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
    var probe = Run(adapter: self, key: key, transport: transport, now: Date())
    return await probe.run()
  }

  /// One probe's state; a value type so the steps read top to bottom.
  struct Run {
    let adapter: OpenAIAdapter
    let key: String
    let transport: any HTTPTransport
    let now: Date
    var capabilities = OpenAIAdapter.capabilities
    var bodies: [String: String] = [:]
    var keys: [DiscoveredKey] = []

    enum Step {
      case passed(Data)
      /// 401/403: the step's capability is off.
      case refused(status: Int)
      /// Ends the probe with this message.
      case failed(String)
    }

    mutating func run() async -> ProbeResult {
      let organization = OpenAIAdapter.organization
      // 1. Admin scope.
      let projects: OpenAIProjectList
      switch await step("projects", "\(organization)/projects", [.init(name: "limit", value: "100")]) {
      case .passed(let body):
        guard let list = decoded(OpenAIProjectList.self, body, "projects") else { return failure(unreadable) }
        projects = list
      case .refused(let status):
        return failure(status == 401 ? CoreStrings.OpenAI.notAdminKey : CoreStrings.OpenAI.missingScope)
      case .failed(let message):
        return failure(message)
      }
      // 2. Keys of every project.
      for project in projects.data {
        let path = OpenAIAdapter.apiKeysPath(project: project.id)
        switch await step("api_keys", path, [.init(name: "limit", value: "100")]) {
        case .passed(let body):
          guard let list = decoded(OpenAIAPIKeyList.self, body, "api_keys") else { return failure(unreadable) }
          keys += list.data.map {
            DiscoveredKey(providerKeyID: $0.id, name: $0.name, redacted: $0.redactedValue, projectID: project.id)
          }
        case .refused:
          capabilities.keyNames = false
        case .failed(let message):
          return failure(message)
        }
      }
      // 3. Usage scope.
      let hourAgo = String(OpenAIAdapter.floor(now.addingTimeInterval(-3600), to: 1))
      let usageQuery: [URLQueryItem] = [
        .init(name: "start_time", value: hourAgo), .init(name: "bucket_width", value: "1h"),
        .init(name: "limit", value: "1")
      ]
      switch await step("usage_completions", "\(organization)/usage/completions", usageQuery) {
      case .passed: break
      case .refused:
        capabilities.usage = false
        capabilities.perKeyUsage = false
      case .failed(let message): return failure(message)
      }
      // 4. Cost scope.
      let dayAgo = String(OpenAIAdapter.floor(now.addingTimeInterval(-86400), to: 1))
      switch await step("costs", "\(organization)/costs",
                        [.init(name: "start_time", value: dayAgo), .init(name: "limit", value: "1")]) {
      case .passed: break
      case .refused: capabilities.cost = false
      case .failed(let message): return failure(message)
      }
      return ProbeResult(capabilities: capabilities, discoveredKeys: keys, currency: capabilities.currencyHint,
                         rawBodiesRedacted: bodies)
    }

    var unreadable: String { CoreStrings.unexpectedResponse(ProviderID.openai.displayName) }

    mutating func step(_ endpoint: String, _ path: String, _ query: [URLQueryItem]) async -> Step {
      let name = ProviderID.openai.displayName
      do {
        let response = try await OpenAIAdapter.send(path, query: query, key: key, transport: transport)
        bodies[endpoint] = RawBody.redacted(response.body, redactor: adapter.log.redactor)
        return .passed(response.body)
      } catch {
        if case .auth(let status, let body) = error {
          bodies[endpoint] = RawBody.truncated(adapter.log.redactor.redact(body))
          return .refused(status: status)
        }
        adapter.log.emit(.error, .pollFailed, cat: .poll(ProviderID.openai.rawValue), msg: "probe step failed",
                         acct: ProviderID.openai.rawValue, job: "probe", err: error, ctx: ["endpoint": .string(endpoint)])
        switch error {
        case .rateLimited: return .failed(CoreStrings.rateLimited(name))
        case .server(let status, let body):
          bodies[endpoint] = RawBody.truncated(adapter.log.redactor.redact(body))
          return .failed(CoreStrings.serverError(name, status: status))
        case .transport, .cancelled: return .failed(CoreStrings.unreachable(name))
        case .decode: return .failed(unreadable)
        case .providerRule(let rule):
          let status = rule.hasPrefix("http ") ? Int(rule.dropFirst(5)) : nil
          return .failed(status.map { CoreStrings.unexpectedStatus(name, status: $0) } ?? unreadable)
        case .auth, .schemaDrift: return .failed(unreadable)
        }
      }
    }

    func decoded<Value: Decodable>(_ type: Value.Type, _ body: Data, _ endpoint: String) -> Value? {
      do {
        let result = try LenientDecoding.decode(type, from: body, endpoint: endpoint)
        adapter.logUnknown(result, job: .keys, now: now)
        return result.value
      } catch {
        adapter.log.emit(.error, .pollSchemaDrift, cat: .poll(ProviderID.openai.rawValue),
                         msg: "probe response could not be decoded", acct: ProviderID.openai.rawValue, job: "probe",
                         err: error, ctx: [
                           "missing_keys": .string(Self.field(error)), "sample": .string(String(bodies[endpoint]?.prefix(512) ?? ""))
                         ])
        return nil
      }
    }

    static func field(_ error: PollError) -> String {
      if case .decode(let field, let path) = error { return "\(field) (\(path))" }
      return "\(error)"
    }

    func failure(_ message: String) -> ProbeResult {
      ProbeResult(capabilities: capabilities, humanMessage: message, discoveredKeys: keys,
                  currency: capabilities.currencyHint, rawBodiesRedacted: bodies)
    }
  }
}
