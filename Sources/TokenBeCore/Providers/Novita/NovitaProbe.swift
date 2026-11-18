import Foundation

/// 02 § novita Probe: `GET /openapi/v1/billing/balance/detail` once. A 200 TokenBe can read passes as `direct`, USD.
/// A refused key → 02's message; a body TokenBe cannot read → `poll.schema_drift` and the unexpected-response
/// message; any other failure → its message. The probe never retries.
extension NovitaAdapter {
  public func probe(key: String, transport: any HTTPTransport) async -> ProbeResult {
    let redactor = log.redactor
    redactor.register(secret: key)
    defer { redactor.unregister(secret: key) }
    let response: HTTPResponse
    do {
      response = try await Self.send(key: key, transport: transport)
    } catch {
      var bodies: [String: String] = [:]
      switch error {
      case .auth(_, let body), .server(_, let body):
        bodies[Self.endpoint] = RawBody.truncated(redactor.redact(body))
      case .transport, .rateLimited, .decode, .schemaDrift, .providerRule, .cancelled:
        break
      }
      log.emit(.error, .pollFailed, cat: .poll(id.rawValue), msg: "probe step failed", acct: id.rawValue,
               job: "probe", err: error, ctx: ["endpoint": .string(Self.endpoint), "attempts": 1])
      return ProbeResult(capabilities: Self.capabilities, humanMessage: error.humanMessage(provider: id),
                         currency: .usd, rawBodiesRedacted: bodies)
    }
    let body = RawBody.redacted(response.body, redactor: redactor)
    do {
      let decoded = try LenientDecoding.decode(NovitaBalance.self, from: response.body, endpoint: Self.endpoint)
      logUnknown(decoded.unknownKeys, now: Date())
    } catch {
      log.emit(.error, .pollSchemaDrift, cat: .poll(id.rawValue), msg: "probe response could not be decoded",
               acct: id.rawValue, job: "probe", err: error,
               ctx: ["missing_keys": .string("\(error)"), "sample": .string(String(body.prefix(512)))])
      return ProbeResult(capabilities: Self.capabilities, humanMessage: CoreStrings.unexpectedResponse(id.displayName),
                         currency: .usd, rawBodiesRedacted: [Self.endpoint: body])
    }
    return ProbeResult(capabilities: Self.capabilities, currency: .usd, rawBodiesRedacted: [Self.endpoint: body])
  }
}
