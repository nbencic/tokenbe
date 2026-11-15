import Foundation

/// xAI's API (02 § xai): `GET /v1/api-key` is both the probe and, for a `direct` account, the 60 s balance poll.
/// Whether the account is `direct` is decided once, by the probe (D-xai-balance): a numeric `remaining_balance` →
/// `direct`, otherwise `anchored` with no balance job. xAI has no usage, cost or key-list endpoint in V1, so those
/// polls keep the protocol's `providerRule` defaults; spend comes from harness reports (06).
public struct XAIAdapter: ProviderAdapter {
  public let id = ProviderID.xai

  /// 02 § Capability matrix, row xai, when the probe finds a balance. `usageLag` is 02's "seconds", read as 60 s.
  public static let capabilities = Capabilities(
    usage: false, cost: false, balance: true, perKeyUsage: false, keyNames: false, balanceModeDefault: .direct,
    usageLag: .seconds(60), currencyHint: .usd
  )

  /// The fallback when the probe finds no usable `remaining_balance` (02: "capabilities.balance = false, mode
  /// anchored").
  public static let anchoredCapabilities = Capabilities(
    usage: false, cost: false, balance: false, perKeyUsage: false, keyNames: false, balanceModeDefault: .anchored,
    usageLag: .seconds(60), currencyHint: .usd
  )

  static let host = "api.x.ai"
  /// 02: base `https://api.x.ai/v1`, endpoint `GET /api-key`.
  static let apiKeyPath = "/v1/api-key"
  static let endpoint = "api_key"
  /// 07 `poll.provider_rule` when the probe falls back to `anchored` (14 § Stage 6.2 step 2).
  static let noBalanceRule = "xai_no_balance_field"

  let log: EventLog
  let once: DailyOnce

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(logPipeline: LogPipeline? = nil) {
    log = EventLog(pipeline: logPipeline)
    once = DailyOnce()
  }

  // MARK: - Balance (02 § Probe + balance; direct accounts only)

  /// One USD `balance_snapshot` from `remaining_balance` (dollars → cents, half up). A direct account whose
  /// response has lost the field fails as `decode`, so the change shows as schema drift, not as a zero balance.
  public func pollBalance(_ context: PollContext) async throws(PollError) -> BalanceReading {
    let response = try await Self.send(key: context.key, transport: context.transport)
    context.trace.record(response.body)
    let decoded = try LenientDecoding.decode(XAIAPIKey.self, from: response.body, endpoint: Self.endpoint)
    logUnknown(decoded.unknownKeys, now: context.window.end)
    guard let remaining = decoded.value.remainingBalance else {
      throw .decode(field: XAIAPIKey.CodingKeys.remainingBalance.rawValue, path: Self.endpoint)
    }
    let snapshot = BalanceSnapshotRecord(
      accountId: context.accountID, ts: DBTime.string(context.window.end), currency: Currency.usd.rawValue,
      amountCents: MinorUnits.cents(remaining), grantedCents: nil, toppedUpCents: nil, isAvailable: nil
    )
    return BalanceReading(snapshots: [snapshot], rawBody: RawBody.redacted(response.body, redactor: log.redactor))
  }

  // MARK: - Requests

  static func send(key: String, transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    try await BearerRequest.get(host: host, path: apiKeyPath, provider: .xai, key: key, transport: transport)
  }

  /// Keys 02 does not list (the key's own metadata, until a recording names it), once per day each
  /// (`poll.unknown_keys`, 07).
  func logUnknown(_ keys: [String], now: Date) {
    let provider = id.rawValue
    let fresh = keys.filter { once.first("poll|\(Job.balance.rawValue)|\($0)", on: now) }
    guard !fresh.isEmpty else { return }
    log.emit(.info, .pollUnknownKeys, cat: .poll(provider), msg: "response has keys 02 does not list",
             acct: provider, job: Job.balance.rawValue, ctx: ["keys": .string(fresh.joined(separator: ","))])
  }
}

#if DEBUG
extension XAIAdapter {
  /// `FixtureTransport` routes (PM-3.3-2).
  public static let fixtureRoutes: [FixtureTransport.Route] = [
    .init(hostPath: "\(host)\(apiKeyPath)", provider: .xai, endpoint: endpoint)
  ]
}
#endif
