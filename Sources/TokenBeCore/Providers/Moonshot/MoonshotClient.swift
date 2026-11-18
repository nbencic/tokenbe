import Foundation

/// Moonshot's (Kimi's) API (02 § moonshot, Q-062): one endpoint, `GET /v1/users/me/balance`, which is both the probe
/// and the balance poll. A key works on one region only: `api.moonshot.ai` answers in USD, `api.moonshot.cn` in CNY.
/// The probe finds the region; the account's currency then names the host (no new column). Moonshot has no usage,
/// cost or key endpoint, so those polls keep the protocol's `providerRule` defaults; per-app spend comes from harness
/// reports (06).
public struct MoonshotAdapter: ProviderAdapter {
  public let id = ProviderID.moonshot

  /// 02 § Capability matrix, row moonshot. `usageLag` labels the Lag badge only (a direct balance has no estimate
  /// band); the docs say real-time consumption "may lag", read as 5 min (Q-062). The currency is the region's.
  public static let capabilities = Capabilities(
    usage: false, cost: false, balance: true, perKeyUsage: false, keyNames: false, balanceModeDefault: .direct,
    usageLag: .seconds(300), currencyHint: .usd
  )

  /// The international platform (USD) and the China platform (CNY).
  static let hostUSD = "api.moonshot.ai"
  static let hostCNY = "api.moonshot.cn"
  static let balancePath = "/v1/users/me/balance"
  static let endpoint = "balance"
  /// 07 `poll.provider_rule`: a 200 whose `status` is false or whose `code` is not 0.
  static let notOKRule = "moonshot_status_not_ok"

  /// The region's host: CNY → China, anything else → international.
  static func host(currency: String) -> String { currency == Currency.cny.rawValue ? hostCNY : hostUSD }

  let log: EventLog
  let once: DailyOnce

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(logPipeline: LogPipeline? = nil) {
    log = EventLog(pipeline: logPipeline)
    once = DailyOnce()
  }

  // MARK: - Balance (02 § Probe + balance)

  /// One `balance_snapshot` in the account's currency: amount `available_balance`, granted `voucher_balance`,
  /// topped up `cash_balance` (negative while the account owes money).
  public func pollBalance(_ context: PollContext) async throws(PollError) -> BalanceReading {
    let response = try await Self.send(key: context.key, host: Self.host(currency: context.currency),
                                       transport: context.transport)
    context.trace.record(response.body)
    let balance = try decode(response.body, now: context.window.end)
    let snapshot = BalanceSnapshotRecord(
      accountId: context.accountID, ts: DBTime.string(context.window.end), currency: context.currency,
      amountCents: balance.availableCents, grantedCents: balance.voucherCents, toppedUpCents: balance.cashCents,
      isAvailable: nil
    )
    return BalanceReading(snapshots: [snapshot], rawBody: RawBody.redacted(response.body, redactor: log.redactor))
  }

  /// The body as a balance; `status == false` or `code != 0` is Moonshot saying the call failed (a provider rule).
  func decode(_ body: Data, now: Date) throws(PollError) -> MoonshotBalance {
    let decoded = try LenientDecoding.decode(MoonshotBalance.self, from: body, endpoint: Self.endpoint)
    logUnknown(decoded.unknownKeys, now: now)
    guard decoded.value.status, decoded.value.code == 0 else { throw .providerRule(Self.notOKRule) }
    return decoded.value
  }

  // MARK: - Requests

  static func send(key: String, host: String, transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    try await BearerRequest.get(host: host, path: balancePath, provider: .moonshot, key: key, transport: transport)
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
extension MoonshotAdapter {
  /// `FixtureTransport` routes (PM-3.3-2): both regions.
  public static let fixtureRoutes: [FixtureTransport.Route] = [
    .init(hostPath: "\(hostUSD)\(balancePath)", provider: .moonshot, endpoint: endpoint),
    .init(hostPath: "\(hostCNY)\(balancePath)", provider: .moonshot, endpoint: "balance_cn")
  ]
}
#endif
