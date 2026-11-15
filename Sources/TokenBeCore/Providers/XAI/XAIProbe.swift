import Foundation

/// 02 § xai Probe: `GET /v1/api-key` once (D-xai-balance). A 2xx with `remaining_balance` as a JSON number passes as
/// `direct` (balance job on). A 2xx without it, with null, or with another type passes as `anchored` (no balance
/// job; onboarding asks for an anchor) and logs `poll.provider_rule rule=xai_no_balance_field`. Any other body
/// TokenBe cannot read fails with the unexpected-response message; other failures with their message. The currency
/// is USD (02). The probe never retries.
extension XAIAdapter {
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
    let bodies = [Self.endpoint: body]
    var remaining: Decimal?
    do {
      let decoded = try LenientDecoding.decode(XAIAPIKey.self, from: response.body, endpoint: Self.endpoint)
      logUnknown(decoded.unknownKeys, now: Date())
      remaining = decoded.value.remainingBalance
    } catch {
      // A `remaining_balance` that is not a number is "no usable balance" (D-xai-balance), logged below as the
      // fallback rule. Anything else is a body TokenBe cannot read.
      guard case .decode(let field, _) = error, field == XAIAPIKey.CodingKeys.remainingBalance.rawValue else {
        log.emit(.error, .pollSchemaDrift, cat: .poll(id.rawValue), msg: "probe response could not be decoded",
                 acct: id.rawValue, job: "probe", err: error,
                 ctx: ["missing_keys": .string("\(error)"), "sample": .string(String(body.prefix(512)))])
        return ProbeResult(capabilities: Self.capabilities, humanMessage: CoreStrings.unexpectedResponse(id.displayName),
                           currency: .usd, rawBodiesRedacted: bodies)
      }
    }
    guard remaining != nil else {
      log.emit(.warn, .pollProviderRule, cat: .poll(id.rawValue), msg: "no usable remaining_balance; anchored",
               acct: id.rawValue, job: "probe", ctx: ["rule": .string(Self.noBalanceRule)])
      return ProbeResult(capabilities: Self.anchoredCapabilities, currency: .usd, rawBodiesRedacted: bodies)
    }
    return ProbeResult(capabilities: Self.capabilities, currency: .usd, rawBodiesRedacted: bodies)
  }
}
