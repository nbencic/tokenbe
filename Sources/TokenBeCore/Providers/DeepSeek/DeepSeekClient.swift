import Foundation

/// DeepSeek's API (02 § deepseek): one endpoint, `GET /user/balance`, which is both the probe and the 60 s balance
/// poll. DeepSeek has no usage, cost or key endpoints, so those polls keep the protocol's `providerRule` defaults
/// (`deepseek_no_usage_api`, 07); per-app spend comes only from harness reports (06, D-deepseek-harness).
public struct DeepSeekAdapter: ProviderAdapter {
  public let id = ProviderID.deepseek

  /// 02 § Capability matrix, row deepseek. `usageLag` is 02's "seconds–minutes" read as its upper end, 5 min; it
  /// only labels the Lag badge, because a direct balance has no estimate band (Q-045). The currency is the first
  /// balance entry's, found by the probe.
  public static let capabilities = Capabilities(
    usage: false, cost: false, balance: true, perKeyUsage: false, keyNames: false, balanceModeDefault: .direct,
    usageLag: .seconds(300), currencyHint: .usd
  )

  static let host = "api.deepseek.com"
  static let balancePath = "/user/balance"
  static let endpoint = "balance"

  let log: EventLog
  let once: DailyOnce

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(logPipeline: LogPipeline? = nil) {
    log = EventLog(pipeline: logPipeline)
    once = DailyOnce()
  }

  // MARK: - Balance (02 § Probe + balance)

  /// One `balance_snapshot` per currency entry, all stamped with the poll's time (03 key `account_id, ts,
  /// currency`). A currency listed twice keeps its first entry.
  public func pollBalance(_ context: PollContext) async throws(PollError) -> BalanceReading {
    let response = try await Self.send(key: context.key, transport: context.transport)
    context.trace.record(response.body)
    let decoded = try LenientDecoding.decode(DeepSeekBalance.self, from: response.body, endpoint: Self.endpoint)
    logUnknown(decoded.unknownKeys, now: context.window.end)
    return BalanceReading(
      snapshots: Self.snapshots(decoded.value, accountID: context.accountID, at: context.window.end),
      rawBody: RawBody.redacted(response.body, redactor: log.redactor)
    )
  }

  static func snapshots(_ balance: DeepSeekBalance, accountID: String, at time: Date) -> [BalanceSnapshotRecord] {
    var seen: Set<String> = []
    return balance.balanceInfos.compactMap { info in
      guard seen.insert(info.currency).inserted else { return nil }
      return BalanceSnapshotRecord(
        accountId: accountID, ts: DBTime.string(time), currency: info.currency, amountCents: info.totalCents,
        grantedCents: info.grantedCents, toppedUpCents: info.toppedUpCents, isAvailable: balance.isAvailable
      )
    }
  }

  // MARK: - Requests

  static func send(key: String, transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    try await BearerRequest.get(host: host, path: balancePath, provider: .deepseek, key: key, transport: transport)
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
extension DeepSeekAdapter {
  /// `FixtureTransport` routes (PM-3.3-2).
  public static let fixtureRoutes: [FixtureTransport.Route] = [
    .init(hostPath: "\(host)\(balancePath)", provider: .deepseek, endpoint: endpoint)
  ]
}
#endif
