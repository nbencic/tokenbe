import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// The price book's snapshot life (11 `PriceFeedTests`; 14 § Stage 5.1 steps 2–4): the bundled seed at first launch,
/// the daily feed (ETag 304, sha256 dedupe, size cap, transport, parse failure keeps the previous snapshot, O-6 shape
/// change, prune to 4), staleness, and overrides. On the real database.
@Suite struct PriceFeedTests {
  static let feedURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
  static let path = feedURL.path()
  static let start = Date(timeIntervalSince1970: 1_794_000_000)   // 2026-11-07T…Z

  /// A price book on a fresh database, with a stub transport and a settable clock.
  struct Harness {
    let store: StoreHarness
    let repository: GRDBRepository
    let transport = StubTransport()
    let date = ManualDate(PriceFeedTests.start)
    let book: PriceBook
    let fetcher: PriceFeedFetcher

    init() async throws {
      store = try StoreHarness()
      repository = GRDBRepository(database: try await store.open().database)
      book = PriceBook(store: repository, logPipeline: store.pipeline, now: date.provider)
      fetcher = PriceFeedFetcher(transport: transport, logPipeline: store.pipeline)
    }

    func refresh(enabled: Bool = true, staleAfterDays: Int = 7) async throws -> PriceFeedFetcher.Outcome? {
      try await book.refresh(fetcher: fetcher, url: PriceFeedTests.feedURL, feedEnabled: enabled,
                             staleAfterDays: staleAfterDays)
    }

    func snapshots() async throws -> [PriceSnapshotRecord] {
      try await repository.database.read { db in try PriceSnapshotRecord.order(Column("version")).fetchAll(db) }
    }

    func records(_ evt: Evt) async -> [LogRecord] { await store.records(evt) }
  }

  static func fixture() throws -> Data { try Data(contentsOf: PriceLookupTests.fixtureURL()) }

  static let bundled = PriceBook.Bundled(data: Data(#"{"gpt-4o":{"mode":"chat","input_cost_per_token":1e-6,"output_cost_per_token":2e-6}}"#.utf8),
                                         sha256: String(repeating: "b", count: 64), appVersion: "1.0.0")

  static func ok(_ body: Data, etag: String? = "\"v1\"") -> StubTransport.Answer {
    .response(HTTPResponse(status: 200, headers: etag.map { ["ETag": $0] } ?? [:], body: body))
  }

  // MARK: - Startup step 4

  @Test("first launch installs the bundled file as bundled-<appversion>, current, and logs price.feed_ok source=bundled")
  func bundledSeed() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    let rows = try await harness.snapshots()
    #expect(rows.count == 1)
    #expect(rows.first?.version == "bundled-1.0.0")
    #expect(rows.first?.isCurrent == true)
    #expect(rows.first?.sha256 == Self.bundled.sha256)
    #expect(rows.first?.json == Self.bundled.data)
    let logged = await harness.records(.priceFeedOk)
    #expect(logged.count == 1)
    #expect(logged.first?.ctx["source"] == "bundled")
    #expect(logged.first?.ctx["entries"] == 1)
    #expect(await harness.book.lookup(provider: .openai, model: "gpt-4o")?.entry.input == 1_000_000)
    let status = await harness.book.status
    #expect(status.version == "bundled-1.0.0")
    #expect(status.models == 1)
    #expect(status.fetchedAt == Self.start)
    #expect(status.isStale == false)
  }

  @Test("a later launch keeps the current snapshot and inserts nothing")
  func secondLaunch() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    let again = PriceBook(store: harness.repository, logPipeline: harness.store.pipeline, now: harness.date.provider)
    try await again.load(bundled: Self.bundled, staleAfterDays: 7)
    #expect(try await harness.snapshots().count == 1)
    #expect(await harness.records(.priceFeedOk).count == 1)
    #expect(await again.lookup(provider: .openai, model: "gpt-4o") != nil)
  }

  @Test("without a bundle or a snapshot every model is unpriced, logged once")
  func noBundle() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: nil, staleAfterDays: 7)
    #expect(await harness.book.lookup(provider: .openai, model: "gpt-4o") == nil)
    #expect(await harness.records(.priceParseFailed).count == 1)
    #expect(try await harness.snapshots().isEmpty)
    #expect(await harness.book.status == PriceBook.Status())
  }

  @Test("a bundle that does not parse leaves the book empty")
  func badBundle() async throws {
    let harness = try await Harness()
    let broken = PriceBook.Bundled(data: Data("nope".utf8), sha256: "x", appVersion: "1")
    try await harness.book.load(bundled: broken, staleAfterDays: 7)
    #expect(try await harness.snapshots().isEmpty)
    #expect(await harness.records(.priceParseFailed).count == 1)
  }

  @Test("a current snapshot that does not parse logs price.parse_failed and the bundled table is used in memory")
  func corruptSnapshot() async throws {
    let harness = try await Harness()
    try await harness.repository.insertCurrentPriceSnapshot(PriceSnapshotRecord(
      version: "2026-11-01", fetchedAt: DBTime.string(Self.start), etag: nil, sha256: "s", json: Data("[".utf8),
      isCurrent: true))
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    #expect(await harness.book.lookup(provider: .openai, model: "gpt-4o")?.entry.output == 2_000_000)
    #expect(await harness.records(.priceParseFailed).first?.ctx["version"] == "2026-11-01")
    #expect(await harness.book.status.version == "2026-11-01")
    #expect(try await harness.snapshots().count == 1)

    let none = PriceBook(store: harness.repository, logPipeline: harness.store.pipeline, now: harness.date.provider)
    try await none.load(bundled: nil, staleAfterDays: 7)
    #expect(await none.lookup(provider: .openai, model: "gpt-4o") == nil)
  }

  // MARK: - Feed

  @Test("a new document becomes the current snapshot, versioned by the UTC day, with its ETag and sha256")
  func newDocument() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    let body = try Self.fixture()
    await harness.transport.on("GET", Self.path, Self.ok(body))
    harness.date.set(Self.start.addingTimeInterval(86_400))
    guard case .new = try await harness.refresh() else { Issue.record("expected a new snapshot"); return }
    let current = try #require(try await harness.repository.fetchCurrentPriceSnapshot())
    #expect(current.version == DailyOnce.utcDay(harness.date.date))
    #expect(current.etag == "\"v1\"")
    #expect(current.sha256 == PriceFeedFetcher.sha256(body))
    #expect(current.json == body)
    #expect(try await harness.snapshots().filter(\.isCurrent).count == 1)
    let logged = try #require(await harness.records(.priceFeedOk).last)
    #expect(logged.ctx["source"] == "feed")
    #expect(logged.ctx["changed"] == true)
    #expect(logged.ctx["entries"] == 9)
    #expect(logged.ctx["bytes"] == .int(body.count))
    #expect(await harness.book.lookup(provider: .anthropic, model: "claude-sonnet-4-5") != nil)
    let request = try #require(await harness.transport.calls.first)
    #expect(request.timeout == 10)
    #expect(request.headers["If-None-Match"] == nil)
  }

  @Test("ETag: the stored ETag is sent; 304 adds no row and moves fetched_at")
  func notModified() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    await harness.transport.on("GET", Self.path, Self.ok(try Self.fixture()),
                               .response(HTTPResponse(status: 304, headers: [:])))
    _ = try await harness.refresh()
    harness.date.set(Self.start.addingTimeInterval(3 * 86_400))
    #expect(try await harness.refresh() == .notModified(etag: "\"v1\""))
    #expect(await harness.transport.calls.last?.headers["If-None-Match"] == "\"v1\"")
    #expect(try await harness.snapshots().count == 2)
    let current = try #require(try await harness.repository.fetchCurrentPriceSnapshot())
    #expect(current.fetchedAt == DBTime.string(harness.date.date))
    let logged = try #require(await harness.records(.priceFeedOk).last)
    #expect(logged.ctx["changed"] == false)
    #expect(await harness.book.status.fetchedAt == harness.date.date)
  }

  @Test("sha256 dedupe: the same body adds no row; a new ETag is kept")
  func sameHash() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    let body = try Self.fixture()
    await harness.transport.on("GET", Self.path, Self.ok(body), Self.ok(body, etag: "\"v2\""))
    _ = try await harness.refresh()
    #expect(try await harness.refresh() == .unchanged(etag: "\"v2\""))
    #expect(try await harness.snapshots().count == 2)
    #expect(try await harness.repository.fetchCurrentPriceSnapshot()?.etag == "\"v2\"")
  }

  @Test("a second new document on the same day replaces that day's row")
  func sameDay() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    let other = Data(#"{"gpt-4o":{"mode":"chat","input_cost_per_token":3e-6,"output_cost_per_token":4e-6}}"#.utf8)
    await harness.transport.on("GET", Self.path, Self.ok(try Self.fixture()), Self.ok(other, etag: nil))
    _ = try await harness.refresh()
    _ = try await harness.refresh()
    let rows = try await harness.snapshots()
    #expect(rows.count == 2)
    #expect(rows.first { $0.isCurrent }?.etag == nil)
    #expect(await harness.book.lookup(provider: .openai, model: "gpt-4o")?.entry.input == 3_000_000)
  }

  @Test("failures keep the current snapshot: transport, HTTP status, size, parse, shape (O-6)",
        arguments: ["transport", "status", "size", "oversize", "parse", "shape"])
  func failures(_ kind: String) async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    let answer: StubTransport.Answer = switch kind {
    case "transport": .failure(.urlError(URLError(.timedOut)))
    case "status": .response(HTTPResponse(status: 500))
    case "size": .failure(.tooLarge(limit: PriceFeedFetcher.maxBytes))
    case "oversize": .response(HTTPResponse(status: 200, body: Data(count: PriceFeedFetcher.maxBytes + 1)))
    case "parse": Self.ok(Data("<html>".utf8))
    default: Self.ok(Data(#"{"a":{"mode":"chat"},"b":{"mode":"chat","input_cost_per_token":1e-6},"c":{"mode":"chat"}}"#.utf8))
    }
    await harness.transport.on("GET", Self.path, answer)
    let outcome = try await harness.refresh()
    let reason = ["status": "transport", "oversize": "size"][kind] ?? kind
    #expect(outcome == .failed(reason: reason))
    #expect(try await harness.snapshots().map(\.version) == ["bundled-1.0.0"])
    #expect(await harness.book.lookup(provider: .openai, model: "gpt-4o")?.entry.input == 1_000_000)
    if kind == "parse" {
      let failed = try #require(await harness.records(.priceParseFailed).last)
      #expect(failed.ctx["bytes"] == 6)
      #expect(failed.lvl == .warn)
    } else {
      let failed = try #require(await harness.records(.priceFeedFailed).last)
      #expect(failed.ctx["reason"] == .string(reason))
      #expect(failed.ctx["using_cached_from"] == "bundled-1.0.0")
      #expect(failed.lvl == .warn)
    }
  }

  @Test("a failure with no snapshot at all names no cached version")
  func failureWithoutSnapshot() async throws {
    let harness = try await Harness()
    await harness.transport.on("GET", Self.path, .failure(.urlError(URLError(.notConnectedToInternet))))
    #expect(try await harness.refresh() == .failed(reason: "transport"))
    #expect(await harness.records(.priceFeedFailed).first?.ctx["using_cached_from"] == .null)
  }

  @Test("a 304 with no current snapshot writes nothing")
  func notModifiedWithoutSnapshot() async throws {
    let harness = try await Harness()
    await harness.transport.on("GET", Self.path, .response(HTTPResponse(status: 304)))
    #expect(try await harness.refresh() == .notModified(etag: nil))
    #expect(try await harness.snapshots().isEmpty)
  }

  @Test("prune keeps 4 snapshots (current + previous 3) and never the current one")
  func prune() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    for day in 1...5 {
      let body = Data(#"{"m\#(day)":{"mode":"chat","input_cost_per_token":1e-6,"output_cost_per_token":1e-6}}"#.utf8)
      await harness.transport.replace("GET", Self.path, Self.ok(body, etag: "\"\(day)\""))
      harness.date.set(Self.start.addingTimeInterval(Double(day) * 86_400))
      _ = try await harness.refresh()
    }
    let rows = try await harness.snapshots()
    #expect(rows.count == PriceBook.keepSnapshots)
    #expect(rows.contains { $0.isCurrent && $0.version == DailyOnce.utcDay(harness.date.date) })
    #expect(!rows.contains { $0.version == "bundled-1.0.0" })
    #expect(try await harness.repository.fetchPriceSnapshotVersions().first == DailyOnce.utcDay(harness.date.date))
    #expect(try await harness.repository.prunePriceSnapshots(keep: 0) == 3)
    #expect(try await harness.snapshots().map(\.isCurrent) == [true])
  }

  @Test("with the feed off nothing is fetched")
  func feedDisabled() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    #expect(try await harness.refresh(enabled: false) == nil)
    #expect(await harness.transport.calls.isEmpty)
  }
}

extension PriceFeedTests {
  // MARK: - Staleness

  @Test("price.stale when the last successful check is older than tb.price.staleAfterDays; a 304 clears it")
  func stale() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    harness.date.set(Self.start.addingTimeInterval(7 * 86_400))
    #expect(await harness.book.checkStale() == false)
    harness.date.set(Self.start.addingTimeInterval(8 * 86_400 + 60))
    #expect(try await harness.refresh(enabled: false) == nil)
    let stale = try #require(await harness.records(.priceStale).last)
    #expect(stale.ctx["snapshot_age_days"] == 8)
    #expect(stale.lvl == .warn)
    #expect(await harness.book.status.isStale)
    await harness.transport.on("GET", Self.path, .response(HTTPResponse(status: 304)))
    _ = try await harness.refresh()
    #expect(await harness.book.status.isStale == false)
    #expect(await harness.records(.priceStale).count == 1)
  }

  @Test("a launch on a stale snapshot logs price.stale")
  func staleAtLaunch() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    harness.date.set(Self.start.addingTimeInterval(30 * 86_400))
    let later = PriceBook(store: harness.repository, logPipeline: harness.store.pipeline, now: harness.date.provider)
    try await later.load(bundled: Self.bundled, staleAfterDays: 60)
    #expect(await harness.records(.priceStale).isEmpty)
    try await later.load(bundled: Self.bundled, staleAfterDays: 14)
    #expect(await harness.records(.priceStale).first?.ctx["snapshot_age_days"] == 30)
  }

  // MARK: - Overrides

  @Test("overrides: set (upsert), remove, reset to feed; each logs price.override_set; lookup follows")
  func overrides() async throws {
    let harness = try await Harness()
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    let entry = PriceEntry(input: 5_000_000, output: 6_000_000)
    try await harness.book.setOverride(model: " gpt-4o ", entry: entry)
    try await harness.book.setOverride(model: "my-model", entry: PriceEntry(input: 1, output: 1))
    #expect(await harness.book.lookup(provider: .openai, model: "gpt-4o")?.entry.input == 5_000_000)
    let rows = try await harness.repository.fetchPriceOverrides()
    #expect(rows.map(\.model) == ["gpt-4o", "my-model"])
    #expect(try PriceEntry(json: rows[0].json).input == 5_000_000)
    #expect(rows[0].updatedAt == DBTime.string(Self.start))
    #expect(await harness.book.status.overrides.map(\.model) == ["gpt-4o", "my-model"])

    try await harness.book.removeOverride(model: "my-model")
    #expect(await harness.book.lookup(provider: .openai, model: "my-model") == nil)
    await #expect(throws: StoreError.notFound("my-model")) { try await harness.book.removeOverride(model: "my-model") }

    try await harness.book.resetToFeed()
    #expect(await harness.book.lookup(provider: .openai, model: "gpt-4o")?.entry.input == 1_000_000)
    #expect(try await harness.repository.fetchPriceOverrides().isEmpty)
    let logged = await harness.records(.priceOverrideSet).map { [$0.ctx["model"], $0.ctx["action"]] }
    #expect(logged == [["gpt-4o", "set"], ["my-model", "set"], ["my-model", "removed"], ["gpt-4o", "reset"]])
  }

  @Test("an override needs a name and positive input and output rates")
  func invalidOverride() async throws {
    let harness = try await Harness()
    await #expect(throws: PriceBook.InvalidOverride()) {
      try await harness.book.setOverride(model: "  ", entry: PriceEntry(input: 1, output: 1))
    }
    await #expect(throws: PriceBook.InvalidOverride()) {
      try await harness.book.setOverride(model: "m", entry: PriceEntry(input: 1, output: 0))
    }
    #expect(try await harness.repository.fetchPriceOverrides().isEmpty)
  }

  @Test("overrides load at launch; one that does not parse is skipped with price.parse_failed")
  func overridesAtLaunch() async throws {
    let harness = try await Harness()
    try await harness.repository.upsertPriceOverride(PriceOverrideRecord(
      model: "gpt-4o", json: PriceEntry(input: 9, output: 9).feedJSON(), updatedAt: DBTime.string(Self.start)))
    try await harness.repository.upsertPriceOverride(PriceOverrideRecord(
      model: "broken", json: "{", updatedAt: DBTime.string(Self.start)))
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    #expect(await harness.book.lookup(provider: .openai, model: "gpt-4o")?.entry.input == 9)
    #expect(await harness.book.status.overrides.map(\.model) == ["gpt-4o"])
    #expect(await harness.records(.priceParseFailed).first?.ctx["model"] == "broken")
    #expect(try await harness.repository.deleteAllPriceOverrides() == 2)
  }

  @Test("updates() yields the status now and after each change")
  func updates() async throws {
    let harness = try await Harness()
    let stream = await harness.book.updates()
    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == PriceBook.Status())
    try await harness.book.load(bundled: Self.bundled, staleAfterDays: 7)
    #expect(await iterator.next()?.version == "bundled-1.0.0")
    try await harness.book.setOverride(model: "m", entry: PriceEntry(input: 1, output: 1))
    #expect(await iterator.next()?.overrides.count == 1)
  }
}
