import Foundation

/// 02 § deepseek Probe: `GET /user/balance` once. A 200 whose first entry names a currency TokenBe can show
/// (`Currency`) passes, and that currency becomes the account's (02: "the account's display currency is the first
/// entry's currency"). A 2xx TokenBe cannot read, or a first currency outside `Currency`, fails with
/// `unexpectedResponse` (Q-045). Every other failure fails with its message. The probe never retries.
/// `is_available == false` still passes: the account shows its balance with the band forced `critical`
/// (D-deepseek-unavailable).
extension DeepSeekAdapter {
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
      return failure(error.humanMessage(provider: id), bodies: bodies)
    }
    let body = RawBody.redacted(response.body, redactor: redactor)
    let bodies = [Self.endpoint: body]
    let balance: DeepSeekBalance
    do {
      let decoded = try LenientDecoding.decode(DeepSeekBalance.self, from: response.body, endpoint: Self.endpoint)
      logUnknown(decoded.unknownKeys, now: Date())
      balance = decoded.value
    } catch {
      var missing = "\(error)"
      if case .decode(let field, let path) = error { missing = "\(field) (\(path))" }
      return drift(missing: missing, body: body, error: error)
    }
    guard let first = balance.balanceInfos.first, let currency = Currency(rawValue: first.currency) else {
      let code = balance.balanceInfos.first?.currency ?? ""
      return drift(missing: "currency (balance: balance_infos[0] = \(code))", body: body,
                   error: PollError.decode(field: "currency", path: "balance: balance_infos[]"))
    }
    return ProbeResult(capabilities: Self.capabilities, currency: currency, rawBodiesRedacted: bodies)
  }

  /// A 2xx body TokenBe cannot use: `poll.schema_drift` with a sample, then 02's unexpected-response message.
  private func drift(missing: String, body: String, error: PollError) -> ProbeResult {
    log.emit(.error, .pollSchemaDrift, cat: .poll(id.rawValue), msg: "probe response could not be decoded",
             acct: id.rawValue, job: "probe", err: error,
             ctx: ["missing_keys": .string(missing), "sample": .string(String(body.prefix(512)))])
    return failure(CoreStrings.unexpectedResponse(id.displayName), bodies: [Self.endpoint: body])
  }

  private func failure(_ message: String, bodies: [String: String]) -> ProbeResult {
    ProbeResult(capabilities: Self.capabilities, humanMessage: message, currency: Self.capabilities.currencyHint,
                rawBodiesRedacted: bodies)
  }
}
