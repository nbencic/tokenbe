import Foundation

/// 02 § moonshot Probe: `GET /v1/users/me/balance` on the international host; a 401 there tries the China host,
/// because a key works on its own region only. The region that answers is the account's currency (USD or CNY). The
/// first 401 is expected for a China key, so it is logged at debug, never as a failure. Both 401 → 02's key-rejected
/// message. A body TokenBe cannot read → the unexpected-response message. The probe never retries.
extension MoonshotAdapter {
  public func probe(key: String, transport: any HTTPTransport) async -> ProbeResult {
    let redactor = log.redactor
    redactor.register(secret: key)
    defer { redactor.unregister(secret: key) }
    var currency = Currency.usd
    var response: HTTPResponse
    do {
      do {
        response = try await Self.send(key: key, host: Self.hostUSD, transport: transport)
      } catch .auth(let status, _) where status == 401 {
        log.emit(.debug, .pollRegionFallback, cat: .poll(id.rawValue), msg: "international host refused the key",
                 acct: id.rawValue, job: "probe",
                 ctx: ["from_host": .string(Self.hostUSD), "to_host": .string(Self.hostCNY), "status": .int(status)])
        currency = .cny
        response = try await Self.send(key: key, host: Self.hostCNY, transport: transport)
      }
    } catch {
      return failure(error, redactor: redactor)
    }
    let body = RawBody.redacted(response.body, redactor: redactor)
    do {
      _ = try decode(response.body, now: Date())
    } catch .providerRule(let rule) {
      log.emit(.error, .pollFailed, cat: .poll(id.rawValue), msg: "probe step failed", acct: id.rawValue,
               job: "probe", err: PollError.providerRule(rule), ctx: ["endpoint": .string(Self.endpoint), "attempts": 1])
      return ProbeResult(capabilities: Self.capabilities, humanMessage: CoreStrings.unexpectedResponse(id.displayName),
                         currency: currency, rawBodiesRedacted: [Self.endpoint: body])
    } catch {
      log.emit(.error, .pollSchemaDrift, cat: .poll(id.rawValue), msg: "probe response could not be decoded",
               acct: id.rawValue, job: "probe", err: error,
               ctx: ["missing_keys": .string("\(error)"), "sample": .string(String(body.prefix(512)))])
      return ProbeResult(capabilities: Self.capabilities, humanMessage: CoreStrings.unexpectedResponse(id.displayName),
                         currency: currency, rawBodiesRedacted: [Self.endpoint: body])
    }
    var capabilities = Self.capabilities
    capabilities.currencyHint = currency
    return ProbeResult(capabilities: capabilities, currency: currency, rawBodiesRedacted: [Self.endpoint: body])
  }

  private func failure(_ error: PollError, redactor: Redactor) -> ProbeResult {
    var bodies: [String: String] = [:]
    if case .auth(_, let body) = error { bodies[Self.endpoint] = RawBody.truncated(redactor.redact(body)) }
    if case .server(_, let body) = error { bodies[Self.endpoint] = RawBody.truncated(redactor.redact(body)) }
    log.emit(.error, .pollFailed, cat: .poll(id.rawValue), msg: "probe step failed", acct: id.rawValue, job: "probe",
             err: error, ctx: ["endpoint": .string(Self.endpoint), "attempts": 1])
    return ProbeResult(capabilities: Self.capabilities, humanMessage: error.humanMessage(provider: id),
                       currency: .usd, rawBodiesRedacted: bodies)
  }
}
