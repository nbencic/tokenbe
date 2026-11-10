import Foundation

/// OpenAI's Admin API (02 § openai): keys, usage and cost polls, and the onboarding probe (`Probe.swift`).
/// Balance does not exist (02 § Balance), so `pollBalance` keeps the protocol's `providerRule` default.
public struct OpenAIAdapter: ProviderAdapter {
  public let id = ProviderID.openai

  /// 02 § Capability matrix, row openai. The probe turns flags off per failed step.
  public static let capabilities = Capabilities(
    usage: true, cost: true, balance: false, perKeyUsage: true, keyNames: true, balanceModeDefault: .anchored,
    usageLag: .seconds(3600), currencyHint: .usd
  )

  static let host = "api.openai.com"
  static let organization = "/v1/organization"
  /// 02 § Usage: `group_by[]=api_key_id&group_by[]=model&group_by[]=service_tier`.
  static let usageGroups = ["api_key_id", "model", "service_tier"]
  /// 02 § Cost: `group_by[]=api_key_id&group_by[]=line_item`.
  static let costGroups = ["api_key_id", "line_item"]
  /// A guard against a cursor that never ends (Q-029); 48 h of 1 h buckets needs a handful of pages.
  static let maxPages = 50

  let log: EventLog
  let once: DailyOnce

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(logPipeline: LogPipeline? = nil) {
    log = EventLog(pipeline: logPipeline)
    once = DailyOnce()
  }

  // MARK: - Keys (02 § Probe steps 1–2)

  public func pollKeys(_ context: PollContext) async throws(PollError) -> KeysPage {
    let projects: Fetched<OpenAIProjectList> = try await get(
      "\(Self.organization)/projects", query: [.init(name: "limit", value: "100")], endpoint: "projects",
      context: context, job: .keys
    )
    var keys: [DiscoveredKey] = []
    var lastBody = projects.body
    for project in projects.value.data {
      let list: Fetched<OpenAIAPIKeyList> = try await get(
        Self.apiKeysPath(project: project.id), query: [.init(name: "limit", value: "100")], endpoint: "api_keys",
        context: context, job: .keys
      )
      lastBody = list.body
      keys += list.value.data.map {
        DiscoveredKey(providerKeyID: $0.id, name: $0.name, redacted: $0.redactedValue, projectID: project.id)
      }
    }
    return KeysPage(keys: keys, rawBody: RawBody.redacted(lastBody, redactor: log.redactor))
  }

  static func apiKeysPath(project: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove("/")
    let encoded = project.addingPercentEncoding(withAllowedCharacters: allowed) ?? project
    return "\(organization)/projects/\(encoded)/api_keys"
  }

  // MARK: - Usage (02 § Usage)

  /// One page. The cursor is `<start_time> <next_page>`: OpenAI's page token belongs to the query it came from, so
  /// a resumed sequence repeats that `start_time` instead of recomputing it (Q-029).
  public func pollUsage(_ context: PollContext) async throws(PollError) -> UsagePage {
    let (start, page) = Self.cursorParts(context.cursor) ?? (Self.floor(context.window.start, to: 3600), nil)
    var query: [URLQueryItem] = [.init(name: "start_time", value: String(start)), .init(name: "bucket_width", value: "1h")]
    query += Self.usageGroups.map { URLQueryItem(name: "group_by[]", value: $0) }
    if let page { query.append(.init(name: "page", value: page)) }
    let decoded: Fetched<OpenAIPage<OpenAIUsageResult>> = try await get(
      "\(Self.organization)/usage/completions", query: query, endpoint: "usage_completions", context: context,
      job: .usage
    )
    let now = context.window.end
    var merged: [UsageKey: UsageBucketRecord] = [:]
    var order: [UsageKey] = []
    var expected = TokenClasses()
    for bucket in decoded.value.data {
      let end = Date(timeIntervalSince1970: TimeInterval(bucket.endTime))
      let provisional = end.addingTimeInterval(Self.lagSeconds) >= now
      for result in bucket.results {
        let classes = OpenAINormalizer.classes(result, log: log)
        expected += classes
        let key = UsageKey(start: bucket.startTime, model: result.model ?? "*", apiKey: result.apiKeyID ?? "",
                           tier: result.serviceTier ?? "")
        if var existing = merged[key] {
          // Two results on one row's key (a null grouping field): summed, so no tokens are lost (V2).
          existing.add(classes)
          existing.provisional = existing.provisional || provisional
          merged[key] = existing
        } else {
          merged[key] = Self.row(context.accountID, key: key, classes: classes, provisional: provisional, now: now)
          order.append(key)
        }
      }
    }
    return UsagePage(
      rows: order.compactMap { merged[$0] }, nextCursor: decoded.value.cursor.map { "\(start) \($0)" },
      rawBody: RawBody.redacted(decoded.body, redactor: log.redactor), expected: expected
    )
  }

  struct UsageKey: Hashable {
    var start: Int64
    var model: String
    var apiKey: String
    var tier: String
  }

  static var lagSeconds: TimeInterval { TimeInterval(capabilities.usageLag.components.seconds) }

  static func row(_ accountID: String, key: UsageKey, classes: TokenClasses, provisional: Bool,
                  now: Date) -> UsageBucketRecord {
    UsageBucketRecord(
      accountId: accountID, bucketStart: DBTime.string(Date(timeIntervalSince1970: TimeInterval(key.start))),
      bucketWidth: "1h", model: key.model, providerKeyId: key.apiKey, serviceTier: key.tier, source: "provider",
      inputUncached: classes.inputUncached, cacheWrite5m: classes.cacheWrite5m, cacheWrite1h: classes.cacheWrite1h,
      cacheRead: classes.cacheRead, output: classes.output, reasoning: classes.reasoning, requests: classes.requests,
      estCostCents: nil, unpriced: false, provisional: provisional, fetchedAt: DBTime.string(now)
    )
  }

  static func cursorParts(_ cursor: String?) -> (Int64, String?)? {
    guard let cursor, let space = cursor.firstIndex(of: " "), let start = Int64(cursor[..<space]) else { return nil }
    let page = String(cursor[cursor.index(after: space)...])
    return (start, page.isEmpty ? nil : page)
  }

  static func floor(_ date: Date, to seconds: Int64) -> Int64 {
    let value = Int64(date.timeIntervalSince1970.rounded(.down))
    return value - ((value % seconds) + seconds) % seconds
  }

  // MARK: - Cost (02 § Cost)

  /// Every page of the window (Q-029). Per UTC day: one `api_key_id` row per key, one `line_item` row per line item
  /// and one `total` row, each summed in `Decimal` and rounded to cents once (half up). `total` is the sum of the
  /// day's results, so each group kind adds up to it before rounding (05 § Spend definitions).
  public func pollCost(_ context: PollContext) async throws(PollError) -> CostPage {
    let start = Self.floor(context.window.start, to: 86400)
    var page: String?
    var buckets: [OpenAIBucket<OpenAICostResult>] = []
    var lastBody = Data()
    for _ in 0..<Self.maxPages {
      var query: [URLQueryItem] = [.init(name: "start_time", value: String(start))]
      query += Self.costGroups.map { URLQueryItem(name: "group_by[]", value: $0) }
      if let page { query.append(.init(name: "page", value: page)) }
      let decoded: Fetched<OpenAIPage<OpenAICostResult>> = try await get(
        "\(Self.organization)/costs", query: query, endpoint: "costs", context: context, job: .cost
      )
      buckets += decoded.value.data
      lastBody = decoded.body
      guard let next = decoded.value.cursor else {
        return CostPage(rows: Self.costRows(buckets, accountID: context.accountID, now: context.window.end),
                        rawBody: RawBody.redacted(lastBody, redactor: log.redactor))
      }
      guard next != page else { throw .providerRule("openai_costs_cursor_repeated") }
      page = next
    }
    throw .providerRule("openai_costs_more_than_\(Self.maxPages)_pages")
  }

  static func costRows(_ buckets: [OpenAIBucket<OpenAICostResult>], accountID: String,
                       now: Date) -> [CostBucketRecord] {
    // Buckets that name the same UTC day are one day (never expected from 1d buckets, but the key is the day).
    var days: [String] = []
    var byDay: [String: (end: Date, results: [OpenAICostResult])] = [:]
    for bucket in buckets {
      let day = DailyOnce.utcDay(Date(timeIntervalSince1970: TimeInterval(bucket.startTime)))
      let end = Date(timeIntervalSince1970: TimeInterval(bucket.endTime))
      if let known = byDay[day] {
        byDay[day] = (max(known.end, end), known.results + bucket.results)
      } else {
        byDay[day] = (end, bucket.results)
        days.append(day)
      }
    }
    var rows: [CostBucketRecord] = []
    for day in days {
      guard let bucket = byDay[day] else { continue }
      let provisional = bucket.end.addingTimeInterval(lagSeconds) >= now
      let currency = bucket.results.first?.amount.currency.uppercased() ?? capabilities.currencyHint.rawValue
      var groups: [CostGroup] = []
      func add(_ kind: String, _ key: String, _ amount: Decimal) {
        if let index = groups.firstIndex(where: { $0.kind == kind && $0.key == key }) {
          groups[index].amount += amount
        } else {
          groups.append(CostGroup(kind: kind, key: key, amount: amount))
        }
      }
      var total = Decimal(0)
      for result in bucket.results {
        add("api_key_id", result.apiKeyID ?? "", result.amount.value)
        add("line_item", result.lineItem ?? "", result.amount.value)
        total += result.amount.value
      }
      groups.append(CostGroup(kind: "total", key: "", amount: total))
      rows += groups.map {
        CostBucketRecord(accountId: accountID, day: day, groupKind: $0.kind, groupKey: $0.key,
                         amountCents: cents($0.amount), currency: currency, provisional: provisional,
                         fetchedAt: DBTime.string(now))
      }
    }
    return rows
  }

  struct CostGroup {
    var kind: String
    var key: String
    var amount: Decimal
  }

  /// Dollars → cents, rounded half up once (05; R7: `Decimal`, never `Double`).
  static func cents(_ dollars: Decimal) -> Int64 {
    var scaled = dollars * 100
    var rounded = Decimal()
    NSDecimalRound(&rounded, &scaled, 0, .plain)
    return NSDecimalNumber(decimal: rounded).int64Value
  }

  // MARK: - Requests

  struct Fetched<Value> {
    var value: Value
    var body: Data
  }

  /// GET with 02's headers; a non-2xx status becomes its `PollError` (04). Unknown keys are logged once per day.
  func get<Value: Decodable>(
    _ path: String, query: [URLQueryItem], endpoint: String, context: PollContext, job: Job
  ) async throws(PollError) -> Fetched<Value> {
    let response = try await Self.send(path, query: query, key: context.key, transport: context.transport)
    context.trace.record(response.body)
    let decoded = try LenientDecoding.decode(Value.self, from: response.body, endpoint: endpoint)
    logUnknown(decoded, job: job, now: context.window.end)
    return Fetched(value: decoded.value, body: response.body)
  }

  static func send(_ path: String, query: [URLQueryItem], key: String,
                   transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = path
    components.queryItems = query.isEmpty ? nil : query
    // `[]` is legal in a query but URLComponents leaves it bare; encode it as 02's endpoints are usually written.
    components.percentEncodedQuery = components.percentEncodedQuery?
      .replacingOccurrences(of: "[", with: "%5B").replacingOccurrences(of: "]", with: "%5D")
    guard let url = components.url else { throw .providerRule("openai_bad_url \(path)") }
    let request = HTTPRequest(url: url, headers: ["Authorization": "Bearer \(key)", "Content-Type": "application/json"])
    let response: HTTPResponse
    do {
      response = try await transport.send(request)
    } catch {
      throw PollError.from(error)
    }
    if let failure = PollError.from(response) { throw failure }
    return response
  }

  func logUnknown<Value>(_ decoded: DecodedBody<Value>, job: Job, now: Date) {
    let provider = id.rawValue
    let fresh = decoded.unknownKeys.filter { once.first("poll|\(job.rawValue)|\($0)", on: now) }
    if !fresh.isEmpty {
      log.emit(.info, .pollUnknownKeys, cat: .poll(provider), msg: "response has keys 02 does not list",
               acct: provider, job: job.rawValue, ctx: ["keys": .string(fresh.joined(separator: ","))])
    }
    let freshUsage = decoded.unknownUsageKeys.filter { once.first("normalize|\($0)", on: now) }
    if !freshUsage.isEmpty {
      log.emit(.info, .normalizeUnknownKeys, cat: .normalize, msg: "usage result has keys 05 does not map",
               ctx: ["provider": .string(provider), "keys": .string(freshUsage.joined(separator: ","))])
    }
  }
}

extension UsageBucketRecord {
  mutating func add(_ classes: TokenClasses) {
    inputUncached += classes.inputUncached
    cacheWrite5m += classes.cacheWrite5m
    cacheWrite1h += classes.cacheWrite1h
    cacheRead += classes.cacheRead
    output += classes.output
    reasoning += classes.reasoning
    requests += classes.requests
  }
}

#if DEBUG
extension OpenAIAdapter {
  /// `FixtureTransport` routes (PM-3.3-2). `proj_fixture` is the project id every fixture carries (11).
  public static let fixtureRoutes: [FixtureTransport.Route] = [
    .init(hostPath: "\(host)\(organization)/projects", provider: .openai, endpoint: "projects"),
    .init(hostPath: "\(host)\(apiKeysPath(project: "proj_fixture"))", provider: .openai, endpoint: "api_keys"),
    .init(hostPath: "\(host)\(organization)/usage/completions", provider: .openai, endpoint: "usage_completions"),
    .init(hostPath: "\(host)\(organization)/costs", provider: .openai, endpoint: "costs")
  ]
}
#endif
