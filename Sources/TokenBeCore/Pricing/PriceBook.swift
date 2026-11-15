import Foundation

/// The price book (05 § Price lookup; 14 § Stage 5.1 step 4): the current snapshot's parsed table and the user's
/// overrides, cached in memory, with lookup, override edits, the feed refresh and the staleness check.
/// One actor in the process (R6); the app creates it at startup step 4 and the daily activity refreshes it.
public actor PriceBook {
  /// The app's bundled snapshot (`Resources/prices.bundled.json` and its `.sha256`).
  public struct Bundled: Sendable {
    public var data: Data
    public var sha256: String
    public var appVersion: String

    public init(data: Data, sha256: String, appVersion: String) {
      self.data = data
      self.sha256 = sha256
      self.appVersion = appVersion
    }

    /// 03: `bundled-<appversion>`.
    public var version: String { "bundled-\(appVersion)" }
  }

  /// One override, as the Price book table shows it.
  public struct Override: Sendable, Equatable, Identifiable {
    public var model: String
    public var entry: PriceEntry
    public var id: String { model }
  }

  /// What Settings → Sources → Price book and the Sources strip's `Prices` chip show.
  public struct Status: Sendable, Equatable {
    /// `2026-11-08` or `bundled-1.0.0`; nil before the first load or when nothing could be loaded.
    public var version: String?
    /// The last successful fetch or check of the current snapshot.
    public var fetchedAt: Date?
    /// Chat entries in the current snapshot.
    public var models: Int
    public var overrides: [Override]
    /// `fetchedAt` is older than `tb.price.staleAfterDays` (09).
    public var isStale: Bool
    /// Distinct models with unpriced usage in the last 90 days (the snapshot line's `N unpriced`, PM-5.1-1, Q-040).
    public var unpricedModels: Int
    /// The rates in use, for pricing outside the actor (the unpriced estimate of the numbers strip).
    public var pricer: Pricer

    public init(version: String? = nil, fetchedAt: Date? = nil, models: Int = 0, overrides: [Override] = [],
                isStale: Bool = false, unpricedModels: Int = 0, pricer: Pricer = Pricer()) {
      self.version = version
      self.fetchedAt = fetchedAt
      self.models = models
      self.overrides = overrides
      self.isStale = isStale
      self.unpricedModels = unpricedModels
      self.pricer = pricer
    }
  }

  /// An override needs a model name and a positive input and output rate (V5).
  public struct InvalidOverride: Error, Sendable, Equatable {}

  /// 14 § Stage 5.1 step 3: `prunePriceSnapshots(keep: 4)` (03: current + previous 3).
  public static let keepSnapshots = 4

  /// 14 § Stage 5.2 step 2: a price change reprices the last 90 days.
  public static let repriceWindow: TimeInterval = 90 * 86_400

  let store: any PriceBookStore
  let log: EventLog
  let now: @Sendable () -> Date
  private var table = PriceTable() {
    didSet { if table != oldValue { revision += 1 } }
  }
  private var overrides: [String: PriceEntry] = [:] {
    didSet { if overrides != oldValue { revision += 1 } }
  }
  private var revision = 0
  /// Models with unpriced usage in the reprice window.
  private var unpriced: Set<String> = []
  /// `price.unpriced` and `price.fallback_multiplier` are logged once per model (and field) per UTC day (05).
  private let once = DailyOnce()
  /// The current snapshot without its blob.
  private var current: PriceSnapshotRecord?
  private var staleAfterDays = 7
  private var observers: [UUID: AsyncStream<Status>.Continuation] = [:]

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(store: any PriceBookStore, logPipeline: LogPipeline? = nil,
              now: @escaping @Sendable () -> Date = { Date() }) {
    self.store = store
    log = EventLog(pipeline: logPipeline)
    self.now = now
  }

  // MARK: - Startup step 4

  /// 04 step 4: load the current snapshot; without one, insert the bundled file as `bundled-<appversion>`, current
  /// (`price.feed_ok {source: bundled}`). Overrides are loaded too, then staleness is checked. A snapshot that does
  /// not parse logs `price.parse_failed` and the bundled table is used in memory; without either, every model is
  /// unpriced. Throws only when the store fails.
  public func load(bundled: Bundled?, staleAfterDays: Int) async throws {
    self.staleAfterDays = staleAfterDays
    if let snapshot = try await store.fetchCurrentPriceSnapshot() {
      if let parsed = parse(snapshot.json, source: snapshot.version) {
        table = parsed
      } else if let bundled, let parsed = parse(bundled.data, source: bundled.version) {
        table = parsed
      }
      current = Self.withoutBlob(snapshot)
    } else if let bundled, let parsed = parse(bundled.data, source: bundled.version) {
      let record = PriceSnapshotRecord(version: bundled.version, fetchedAt: DBTime.string(now()), etag: nil,
                                       sha256: bundled.sha256, json: bundled.data, isCurrent: true)
      try await store.insertCurrentPriceSnapshot(record)
      table = parsed
      current = Self.withoutBlob(record)
      log.emit(.info, .priceFeedOk, cat: .price, msg: "bundled price snapshot installed", ctx: [
        "source": "bundled", "entries": .int(parsed.entries.count), "etag": .null, "bytes": .int(bundled.data.count),
        "version": .string(bundled.version)
      ])
    } else if bundled == nil {
      log.emit(.warn, .priceParseFailed, cat: .price, msg: "no price snapshot: every model is unpriced",
               err: MissingBundle(), ctx: ["bytes": 0])
    }
    try await loadOverrides()
    try await loadUnpriced()
    checkStale()
    publish()
  }

  /// The bundled resource was not in the app.
  struct MissingBundle: Error, CustomStringConvertible {
    var description: String { "prices.bundled.json is missing" }
  }

  private func parse(_ data: Data, source: String) -> PriceTable? {
    do {
      return try PriceTable.parse(data)
    } catch {
      log.emit(.warn, .priceParseFailed, cat: .price, msg: "price snapshot does not parse", err: error,
               ctx: ["bytes": .int(data.count), "version": .string(source)])
      return nil
    }
  }

  private func loadOverrides() async throws {
    var loaded: [String: PriceEntry] = [:]
    for row in try await store.fetchPriceOverrides() {
      do {
        loaded[row.model] = try PriceEntry(json: row.json)
      } catch {
        log.emit(.warn, .priceParseFailed, cat: .price, msg: "price override does not parse", err: error,
                 ctx: ["bytes": .int(row.json.utf8.count), "model": .string(row.model)])
      }
    }
    overrides = loaded
  }

  // MARK: - Lookup

  /// 05 § Price lookup over the overrides and the current snapshot; nil is unpriced (never a zero price, V5).
  /// The hit carries the entry and the step that found it.
  public func lookup(provider: ProviderID, model: String) -> Lookup.Hit? {
    Lookup.find(provider: provider, model: model, overrides: overrides, feed: table.entries)
  }

  // MARK: - Overrides

  /// Inserts or replaces the model's override (`price.override_set {model, action: set}`).
  public func setOverride(model: String, entry: PriceEntry) async throws {
    let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, entry.isPriced else { throw InvalidOverride() }
    try await store.upsertPriceOverride(
      PriceOverrideRecord(model: name, json: entry.feedJSON(), updatedAt: DBTime.string(now()))
    )
    overrides[name] = entry
    log.emit(.info, .priceOverrideSet, cat: .price, msg: "price override set",
             ctx: ["model": .string(name), "action": "set"])
    try await repriceAll()
    publish()
  }

  /// `−` in the overrides table (`price.override_set {model, action: removed}`).
  public func removeOverride(model: String) async throws {
    try await store.deletePriceOverride(model: model)
    overrides[model] = nil
    log.emit(.info, .priceOverrideSet, cat: .price, msg: "price override removed",
             ctx: ["model": .string(model), "action": "removed"])
    try await repriceAll()
    publish()
  }

  /// `Reset to feed`: every override is removed, so every model uses the feed again (Q-038).
  public func resetToFeed() async throws {
    let models = overrides.keys.sorted()
    try await store.deleteAllPriceOverrides()
    overrides = [:]
    for model in models {
      log.emit(.info, .priceOverrideSet, cat: .price, msg: "price override removed",
               ctx: ["model": .string(model), "action": "reset"])
    }
    try await repriceAll()
    publish()
  }

  // MARK: - Refresh (daily step `price refresh`, `Refresh now`)

  /// One feed check: a new document becomes the current snapshot (`version` = the UTC day of the fetch) and old
  /// snapshots are pruned to 4; an unchanged feed (304 or same sha256) only moves `fetched_at`; a failure keeps
  /// the current snapshot (logged by the fetcher). Staleness is checked after every refresh. With the feed off
  /// (`tb.price.feedEnabled = false`) nothing is fetched. Throws only when the store fails.
  @discardableResult
  public func refresh(fetcher: PriceFeedFetcher, url: URL, feedEnabled: Bool,
                      staleAfterDays: Int) async throws -> PriceFeedFetcher.Outcome? {
    self.staleAfterDays = staleAfterDays
    guard feedEnabled else {
      checkStale()
      publish()
      return nil
    }
    let outcome = await fetcher.fetch(url: url, current: current)
    let stamp = DBTime.string(now())
    switch outcome {
    case .notModified(let etag), .unchanged(let etag):
      if let version = current?.version {
        try await store.touchPriceSnapshot(version: version, fetchedAt: stamp, etag: etag)
        current?.fetchedAt = stamp
        if let etag { current?.etag = etag }
      }
      log.emit(.info, .priceFeedOk, cat: .price, msg: "price feed unchanged", ctx: [
        "source": "feed", "changed": false, "entries": .int(table.entries.count),
        "etag": etag.map { .string($0) } ?? .null, "bytes": 0
      ])
    case let .new(body, etag, sha, parsed):
      let record = PriceSnapshotRecord(version: DailyOnce.utcDay(now()), fetchedAt: stamp, etag: etag, sha256: sha,
                                       json: body, isCurrent: true)
      try await store.insertCurrentPriceSnapshot(record)
      try await store.prunePriceSnapshots(keep: Self.keepSnapshots)
      table = parsed
      current = Self.withoutBlob(record)
      log.emit(.info, .priceFeedOk, cat: .price, msg: "price feed refreshed", ctx: [
        "source": "feed", "changed": true, "entries": .int(parsed.entries.count),
        "etag": etag.map { .string($0) } ?? .null, "bytes": .int(body.count), "version": .string(record.version)
      ])
      try await repriceAll()
    case .failed:
      break
    }
    checkStale()
    publish()
    return outcome
  }

  // MARK: - Staleness

  /// `price.stale {snapshot_age_days}` when the current snapshot's last successful fetch or check is older than
  /// `tb.price.staleAfterDays` (09). Checked at launch and after each refresh.
  @discardableResult
  public func checkStale() -> Bool {
    guard let fetched = current.flatMap({ DBTime.date($0.fetchedAt) }) else { return false }
    let age = now().timeIntervalSince(fetched)
    let stale = age > Double(staleAfterDays) * 86_400
    if stale {
      log.emit(.warn, .priceStale, cat: .price, msg: "price snapshot is stale",
               ctx: ["snapshot_age_days": .int(Int(age / 86_400)), "version": .string(current?.version ?? "")])
    }
    return stale
  }

  // MARK: - Status

  public var status: Status {
    let fetched = current.flatMap { DBTime.date($0.fetchedAt) }
    return Status(
      version: current?.version, fetchedAt: fetched, models: table.entries.count,
      overrides: overrides.map { Override(model: $0.key, entry: $0.value) }.sorted { $0.model < $1.model },
      isStale: fetched.map { now().timeIntervalSince($0) > Double(staleAfterDays) * 86_400 } ?? false,
      unpricedModels: unpriced.count, pricer: pricer
    )
  }

  /// The status now, then once per change (load, refresh, override edit).
  public func updates() -> AsyncStream<Status> {
    let (stream, continuation) = AsyncStream.makeStream(of: Status.self)
    let id = UUID()
    observers[id] = continuation
    continuation.onTermination = { [weak self] _ in Task { await self?.unregister(id) } }
    continuation.yield(status)
    return stream
  }

  private func unregister(_ id: UUID) {
    observers[id] = nil
  }

  private func publish() {
    let value = status
    for continuation in observers.values { continuation.yield(value) }
  }

  static func withoutBlob(_ record: PriceSnapshotRecord) -> PriceSnapshotRecord {
    var copy = record
    copy.json = Data()
    return copy
  }
}

/// Cost estimation (14 § Stage 5.2): pricing rows before they are written, and repricing after a price change.
extension PriceBook {
  // MARK: - Cost estimation (14 § Stage 5.2)

  /// The rates in use, as a value (`repriceUsage` prices inside a database transaction, outside this actor).
  public var pricer: Pricer {
    Pricer(overrides: overrides, feed: table.entries, revision: revision)
  }

  /// Every row with `est_cost_cents` and `unpriced` set (05 § Cost formula), just before it is written. Logs
  /// `price.unpriced` and `price.fallback_multiplier` once per model (and field) per UTC day.
  public func price(_ rows: [UsageBucketRecord], provider: ProviderID) -> [UsageBucketRecord] {
    let current = pricer
    let before = unpriced
    let priced = rows.map { row in
      let (copy, estimate) = current.price(row, provider: provider)
      record(estimate, provider: provider, model: row.model)
      return copy
    }
    if unpriced != before { publish() }
    return priced
  }

  private func record(_ estimate: CostEstimator.Estimate, provider: ProviderID, model: String) {
    let time = now()
    let base: [String: LogValue] = ["provider": .string(provider.rawValue), "model": .string(model)]
    if estimate.isUnpriced {
      unpriced.insert(model)
      if once.first("unpriced \(provider.rawValue) \(model)", on: time) {
        log.emit(.warn, .priceUnpriced, cat: .price, msg: "model has no price", ctx: base)
      }
      return
    }
    unpriced.remove(model)
    for field in estimate.fallbackFields where once.first("fallback \(provider.rawValue) \(model) \(field)", on: time) {
      log.emit(.info, .priceFallbackMultiplier, cat: .price, msg: "fallback multiplier used",
               ctx: base.merging(["field": .string(field)]) { $1 })
    }
    if estimate.tierPricedAsStandard, once.first("tier \(provider.rawValue) \(model)", on: time) {
      log.emit(.info, .priceFallbackMultiplier, cat: .price, msg: "tier priced as standard",
               ctx: base.merging(["field": "service_tier", "tier_priced_as_standard": true]) { $1 })
    }
  }

  /// 14 § Stage 5.2 step 2: after the current snapshot or an override changes, every account's buckets of the last
  /// 90 days are priced again, one transaction per account (`price.repriced {acct, rows, snapshot_version}`).
  public func repriceAll() async throws {
    let current = pricer
    let since = DBTime.string(now().addingTimeInterval(-Self.repriceWindow))
    for account in try await store.fetchAccounts() {
      guard let provider = ProviderID(rawValue: account.provider) else { continue }
      let rows = try await store.repriceUsage(accountID: account.id, since: since) { current.price($0, provider: provider).0 }
      log.emit(.info, .priceRepriced, cat: .price, msg: "usage repriced", acct: account.provider, ctx: [
        "rows": .int(rows), "snapshot_version": .string(self.current?.version ?? "")
      ])
    }
    try await loadUnpriced()
  }

  private func loadUnpriced() async throws {
    unpriced = Set(try await store.fetchUnpricedModels(since: DBTime.string(now().addingTimeInterval(-Self.repriceWindow))))
  }
}

/// What the price book reads and writes: prices, the accounts to reprice and their usage rows.
public typealias PriceBookStore = PriceRepository & AccountRepository & UsageRepository

/// A value copy of the overrides and the current table (05 § Price lookup), so rows can be priced outside the
/// `PriceBook` actor. Two pricers are equal when they come from the same revision of the book.
public struct Pricer: Sendable, Equatable {
  public var overrides: [String: PriceEntry]
  public var feed: [String: PriceEntry]
  var revision: Int

  public init(overrides: [String: PriceEntry] = [:], feed: [String: PriceEntry] = [:], revision: Int = 0) {
    self.overrides = overrides
    self.feed = feed
    self.revision = revision
  }

  public static func == (lhs: Pricer, rhs: Pricer) -> Bool {
    lhs.revision == rhs.revision && lhs.overrides.count == rhs.overrides.count && lhs.feed.count == rhs.feed.count
  }

  public func lookup(provider: ProviderID, model: String) -> Lookup.Hit? {
    Lookup.find(provider: provider, model: model, overrides: overrides, feed: feed)
  }

  /// The row priced by 05 § Cost formula.
  public func price(_ row: UsageBucketRecord, provider: ProviderID) -> (UsageBucketRecord, CostEstimator.Estimate) {
    CostEstimator.priced(row, entry: lookup(provider: provider, model: row.model)?.entry)
  }
}
