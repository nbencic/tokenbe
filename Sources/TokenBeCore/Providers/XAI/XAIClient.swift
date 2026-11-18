import Foundation

/// xAI's Management API (02 § xai, Q-062). The key is a management key. TokenBe calls exactly two paths: `GET
/// /auth/management-keys/validation` (the key's team) and `POST /v1/billing/teams/{team_id}/usage` (daily USD per
/// model). The account is anchored: its spend comes from the cost job, its balance from the user's anchor, until H6
/// records `GET …/prepaid/balance` and shows what its `total` means. No other management path is ever called; the key
/// can also buy credit and change limits, which TokenBe never does (10.0.2.sh checks).
public struct XAIAdapter: ProviderAdapter {
  public let id = ProviderID.xai

  /// 02 § Capability matrix, row xai: cost only, anchored, USD. `usageLag` is the usage explorer's, unpublished; one
  /// hour is assumed, so today's and the last hour's rows stay provisional (Q-062).
  public static let capabilities = Capabilities(
    usage: false, cost: true, balance: false, perKeyUsage: false, keyNames: false, balanceModeDefault: .anchored,
    usageLag: .seconds(3600), currencyHint: .usd
  )

  static let host = "management-api.x.ai"
  static let validationPath = "/auth/management-keys/validation"
  static let validationEndpoint = "validation"
  static let usageEndpoint = "usage"
  /// 07 `poll.provider_rule`: the usage answer was cut short (`limitReached`); the rows it has are kept.
  static let limitReachedRule = "xai_usage_limit_reached"
  /// 07 `poll.provider_rule` / probe: the key names no team (an organization-scoped management key).
  static let noTeamRule = "xai_key_has_no_team"

  static func usagePath(team: String) -> String { "/v1/billing/teams/\(team)/usage" }
  static func usageTarget(team: String) -> BearerRequest.Target {
    BearerRequest.Target(host: host, path: usagePath(team: team), provider: .xai)
  }

  let log: EventLog
  let once: DailyOnce

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(logPipeline: LogPipeline? = nil) {
    log = EventLog(pipeline: logPipeline)
    once = DailyOnce()
  }

  // MARK: - Cost (02 § xai Cost job)

  /// The team, then the window's usage: per UTC day, one `description` row per model and one `total` row, summed in
  /// `Decimal` and rounded to cents once (half up, 05). Days the provider may still be counting are provisional.
  public func pollCost(_ context: PollContext) async throws(PollError) -> CostPage {
    let team = try await team(key: context.key, transport: context.transport, trace: context.trace,
                              now: context.window.end)
    let request = XAIUsageRequest(start: context.window.start, end: context.window.end)
    let response = try await BearerRequest.post(
      Self.usageTarget(team: team), key: context.key, json: request.json(), transport: context.transport
    )
    context.trace.record(response.body)
    let decoded = try LenientDecoding.decode(XAIUsage.self, from: response.body, endpoint: Self.usageEndpoint)
    logUnknown(decoded.unknownKeys, job: .cost, now: context.window.end)
    if decoded.value.limitReached, once.first("rule|\(Self.limitReachedRule)", on: context.window.end) {
      log.emit(.warn, .pollProviderRule, cat: .poll(id.rawValue), msg: "usage answer is partial (limitReached)",
               acct: id.rawValue, job: Job.cost.rawValue, ctx: ["rule": .string(Self.limitReachedRule)])
    }
    let rows = try Self.costRows(decoded.value, accountID: context.accountID, now: context.window.end)
    return CostPage(rows: rows, rawBody: RawBody.redacted(response.body, redactor: log.redactor))
  }

  static func costRows(_ usage: XAIUsage, accountID: String, now: Date) throws(PollError) -> [CostBucketRecord] {
    var days: [String] = []
    var byDay: [String: [(model: String, usd: Decimal)]] = [:]
    for series in usage.timeSeries {
      let model = series.group.first ?? ""
      for point in series.dataPoints {
        guard let day = Self.day(point.timestamp) else {
          throw .decode(field: "timestamp", path: "\(usageEndpoint): timeSeries[].dataPoints[]")
        }
        let usd = point.values.first ?? 0
        if byDay[day] == nil { days.append(day) }
        byDay[day, default: []].append((model, usd))
      }
    }
    var rows: [CostBucketRecord] = []
    for day in days.sorted() {
      let entries = byDay[day] ?? []
      let provisional = Self.dayEnd(day).addingTimeInterval(lagSeconds) >= now
      var models: [String] = []
      var amounts: [String: Decimal] = [:]
      for entry in entries {
        if amounts[entry.model] == nil { models.append(entry.model) }
        amounts[entry.model, default: 0] += entry.usd
      }
      func row(_ kind: String, _ key: String, _ usd: Decimal) -> CostBucketRecord {
        CostBucketRecord(accountId: accountID, day: day, groupKind: kind, groupKey: key,
                         amountCents: MinorUnits.cents(usd), currency: Currency.usd.rawValue, provisional: provisional,
                         fetchedAt: DBTime.string(now))
      }
      rows += models.map { row("description", $0, amounts[$0] ?? 0) }
      rows.append(row("total", "", entries.reduce(Decimal(0)) { $0 + $1.usd }))
    }
    return rows
  }

  static var lagSeconds: TimeInterval { TimeInterval(capabilities.usageLag.components.seconds) }

  /// `2025-10-01T00:00:00Z` → `2025-10-01`; nil for anything else.
  static func day(_ timestamp: String) -> String? {
    let day = String(timestamp.prefix(10))
    guard day.count == 10, DBTime.date("\(day)T00:00:00.000Z") != nil else { return nil }
    return day
  }

  /// The end of a UTC day (the next midnight).
  static func dayEnd(_ day: String) -> Date {
    (DBTime.date("\(day)T00:00:00.000Z") ?? .distantPast).addingTimeInterval(86400)
  }

  // MARK: - Requests

  /// The key's team (02): `scopeId` for a team-scoped key, else the deprecated `teamId`. A key with neither fails
  /// as a provider rule, with the probe's message.
  func team(key: String, transport: any HTTPTransport, trace: ResponseTrace?, now: Date) async throws(PollError)
    -> String {
    let response = try await BearerRequest.get(host: Self.host, path: Self.validationPath, provider: .xai, key: key,
                                               transport: transport)
    trace?.record(response.body)
    let decoded = try LenientDecoding.decode(XAIValidation.self, from: response.body,
                                             endpoint: Self.validationEndpoint)
    logUnknown(decoded.unknownKeys, job: nil, now: now)
    guard let team = decoded.value.team else { throw .providerRule(Self.noTeamRule) }
    return team
  }

  /// Keys 02 does not list, once per day each (`poll.unknown_keys`, 07).
  func logUnknown(_ keys: [String], job: Job?, now: Date) {
    let provider = id.rawValue
    let jobName = job?.rawValue ?? "probe"
    let fresh = keys.filter { once.first("poll|\(jobName)|\($0)", on: now) }
    guard !fresh.isEmpty else { return }
    log.emit(.info, .pollUnknownKeys, cat: .poll(provider), msg: "response has keys 02 does not list",
             acct: provider, job: jobName, ctx: ["keys": .string(fresh.joined(separator: ","))])
  }
}

#if DEBUG
extension XAIAdapter {
  /// The team of the synthetic validation fixture (`validation.ok.synthetic.json`).
  public static let fixtureTeam = "team_fixture"

  /// `FixtureTransport` routes (PM-3.3-2).
  public static let fixtureRoutes: [FixtureTransport.Route] = [
    .init(hostPath: "\(host)\(validationPath)", provider: .xai, endpoint: validationEndpoint),
    .init(method: "POST", hostPath: "\(host)\(usagePath(team: fixtureTeam))", provider: .xai,
          endpoint: usageEndpoint)
  ]
}
#endif
