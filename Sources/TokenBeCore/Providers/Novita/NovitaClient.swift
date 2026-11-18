import Foundation

/// Novita's API (02 § novita, Q-062): `GET /openapi/v1/billing/balance/detail` is both the probe and the balance
/// poll, with the account's inference key. Amounts are USD in 1/10000 units. TokenBe reads no usage, cost or key
/// endpoint (its per-key bill list is not used in V1), so those polls keep the protocol's `providerRule` defaults;
/// per-app spend comes from harness reports (06).
public struct NovitaAdapter: ProviderAdapter {
  public let id = ProviderID.novita

  /// 02 § Capability matrix, row novita. `usageLag` labels the Lag badge only (no estimate band for a direct
  /// balance); Novita documents none, read as 5 min (Q-062).
  public static let capabilities = Capabilities(
    usage: false, cost: false, balance: true, perKeyUsage: false, keyNames: false, balanceModeDefault: .direct,
    usageLag: .seconds(300), currencyHint: .usd
  )

  static let host = "api.novita.ai"
  static let balancePath = "/openapi/v1/billing/balance/detail"
  static let endpoint = "balance"

  let log: EventLog
  let once: DailyOnce

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(logPipeline: LogPipeline? = nil) {
    log = EventLog(pipeline: logPipeline)
    once = DailyOnce()
  }

  // MARK: - Balance (02 § Probe + balance)

  /// One USD `balance_snapshot`: amount `availableBalance` (what can be spent, credit limit included), topped up
  /// `cashBalance`.
  public func pollBalance(_ context: PollContext) async throws(PollError) -> BalanceReading {
    let response = try await Self.send(key: context.key, transport: context.transport)
    context.trace.record(response.body)
    let decoded = try LenientDecoding.decode(NovitaBalance.self, from: response.body, endpoint: Self.endpoint)
    logUnknown(decoded.unknownKeys, now: context.window.end)
    let snapshot = BalanceSnapshotRecord(
      accountId: context.accountID, ts: DBTime.string(context.window.end), currency: Currency.usd.rawValue,
      amountCents: decoded.value.availableCents, grantedCents: nil, toppedUpCents: decoded.value.cashCents,
      isAvailable: nil
    )
    return BalanceReading(snapshots: [snapshot], rawBody: RawBody.redacted(response.body, redactor: log.redactor))
  }

  // MARK: - Requests

  static func send(key: String, transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    try await BearerRequest.get(host: host, path: balancePath, provider: .novita, key: key, transport: transport)
  }

  /// Keys 02 does not list, once per day each (`poll.unknown_keys`, 07).
  func logUnknown(_ keys: [String], now: Date) {
    let provider = id.rawValue
    let fresh = keys.filter { once.first("poll|\(Job.balance.rawValue)|\($0)", on: now) }
    guard !fresh.isEmpty else { return }
    log.emit(.info, .pollUnknownKeys, cat: .poll(provider), msg: "response has keys 02 does not list",
             acct: provider, job: Job.balance.rawValue, ctx: ["keys": .string(fresh.joined(separator: ","))])
  }
}

#if DEBUG
extension NovitaAdapter {
  /// `FixtureTransport` routes (PM-3.3-2).
  public static let fixtureRoutes: [FixtureTransport.Route] = [
    .init(hostPath: "\(host)\(balancePath)", provider: .novita, endpoint: endpoint)
  ]
}
#endif
