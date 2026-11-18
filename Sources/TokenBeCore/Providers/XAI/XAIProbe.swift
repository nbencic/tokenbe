import Foundation

/// 02 § xai Probe (Q-062): `GET /auth/management-keys/validation` names the key's team; one `POST …/usage` over the
/// last day proves the key may read that team's billing. Both pass → anchored with the cost job, USD (onboarding then
/// asks for an anchor). A refused key, a key with no team, a body TokenBe cannot read, or any other failure ends with
/// its message. The probe never retries.
extension XAIAdapter {
  public func probe(key: String, transport: any HTTPTransport) async -> ProbeResult {
    let redactor = log.redactor
    redactor.register(secret: key)
    defer { redactor.unregister(secret: key) }
    let trace = ResponseTrace()
    var endpoint = Self.validationEndpoint
    do {
      let now = Date()
      let team = try await team(key: key, transport: transport, trace: trace, now: now)
      endpoint = Self.usageEndpoint
      let request = XAIUsageRequest(start: now.addingTimeInterval(-86400), end: now)
      let response = try await BearerRequest.post(Self.usageTarget(team: team), key: key, json: try request.json(),
                                                  transport: transport)
      trace.record(response.body)
      let decoded = try LenientDecoding.decode(XAIUsage.self, from: response.body, endpoint: Self.usageEndpoint)
      logUnknown(decoded.unknownKeys, job: nil, now: now)
      // The rows the cost job would write: a body it could not use fails here, not at the first poll.
      _ = try Self.costRows(decoded.value, accountID: "", now: now)
      return ProbeResult(capabilities: Self.capabilities, currency: .usd,
                         rawBodiesRedacted: [endpoint: RawBody.redacted(response.body, redactor: redactor)])
    } catch {
      return failure(error, endpoint: endpoint, body: trace.lastBody, redactor: redactor)
    }
  }

  /// Logs the failed step (`poll.schema_drift` with a sample for a body TokenBe cannot read, else `poll.failed`) and
  /// returns its message: 02's copy for a refused key or a key with no team, the unexpected-response message for an
  /// unreadable body, the transport's message otherwise.
  private func failure(_ error: PollError, endpoint: String, body: Data?, redactor: Redactor) -> ProbeResult {
    var bodies: [String: String] = [:]
    let message: String
    switch error {
    case .auth(_, let body), .server(_, let body):
      bodies[endpoint] = RawBody.truncated(redactor.redact(body))
      message = error.humanMessage(provider: id)
    case .providerRule(let rule) where rule == Self.noTeamRule:
      message = CoreStrings.XAI.noTeam
    case .decode(let field, let path):
      let sample = body.map { RawBody.redacted($0, redactor: redactor) } ?? ""
      bodies[endpoint] = sample
      log.emit(.error, .pollSchemaDrift, cat: .poll(id.rawValue), msg: "probe response could not be decoded",
               acct: id.rawValue, job: "probe", err: error,
               ctx: ["missing_keys": .string("\(field) (\(path))"), "sample": .string(String(sample.prefix(512)))])
      return ProbeResult(capabilities: Self.capabilities, humanMessage: CoreStrings.unexpectedResponse(id.displayName),
                         currency: .usd, rawBodiesRedacted: bodies)
    case .transport, .rateLimited, .schemaDrift, .providerRule, .cancelled:
      message = error.humanMessage(provider: id)
    }
    log.emit(.error, .pollFailed, cat: .poll(id.rawValue), msg: "probe step failed", acct: id.rawValue, job: "probe",
             err: error, ctx: ["endpoint": .string(endpoint), "attempts": 1])
    return ProbeResult(capabilities: Self.capabilities, humanMessage: message, currency: .usd,
                       rawBodiesRedacted: bodies)
  }
}
