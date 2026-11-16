import Foundation
import GRDB
import Synchronization
import Testing
@testable import TokenBeCore

/// The test `FileWatcher` (14 § 0.3): yields when the test calls `fire()`; `failing` throws like an FSEvents stream
/// that cannot start.
final class ManualWatcher: FileWatcher, Sendable {
  struct Unavailable: Error {}

  let failing: Bool
  private let continuations = Mutex<[AsyncStream<[String]>.Continuation]>([])

  init(failing: Bool = false) {
    self.failing = failing
  }

  func changes(in directory: URL) throws -> AsyncStream<[String]> {
    if failing { throw Unavailable() }
    let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
    continuations.withLock { $0.append(continuation) }
    return stream
  }

  func fire() {
    continuations.withLock { list in for continuation in list { continuation.yield([]) } }
  }

  var watching: Bool { continuations.withLock { !$0.isEmpty } }
}

/// An `IngestService` over a real database in a temp folder, with a manual watcher and a test clock (06, 11
/// `IngestTailerTests`). The drop folder is `<temp>/ingest`, never the owner's.
struct IngestHarness {
  static let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00:00Z
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fixtures/harness")
  static let deepseekAccount = "acct-deepseek"

  let store: StoreHarness
  let database: AppDatabase
  let repository: GRDBRepository
  let clock = TestClock()
  let watcher: ManualWatcher
  let fallback: ManualWatcher
  let service: IngestService
  let folder: URL

  init(settings: IngestSettings = IngestSettings(), failingWatcher: Bool = false,
       now: @escaping @Sendable () -> Date = { IngestHarness.now }, deepSeekAccount: Bool = true) async throws {
    store = try StoreHarness()
    database = try await store.open().database
    repository = GRDBRepository(database: database)
    folder = store.temp.url.appendingPathComponent("ingest", isDirectory: true)
    watcher = ManualWatcher(failing: failingWatcher)
    fallback = ManualWatcher()
    if deepSeekAccount {
      try await repository.insertAccount(FixtureDBBuilder.account(id: Self.deepseekAccount, provider: "deepseek",
                                                                  label: "DeepSeek"))
      try await repository.upsertProviderKeys(accountID: Self.deepseekAccount, keys: [
        DiscoveredKey(providerKeyID: "dskey-1", name: "main", redacted: "sk-...a9f2")
      ], seenAt: Self.now)
    }
    let pricer = Pricer(feed: try PriceLookupTests.feed())
    service = IngestService(folder: folder, store: repository, watcher: watcher, fallback: fallback, clock: clock,
                            settings: settings, pricer: { pricer }, now: now, logPipeline: store.pipeline)
  }

  /// Copies a fixture into the drop folder (as `name`).
  func drop(_ fixture: String, as name: String? = nil) throws {
    try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(fixture),
                                     to: folder.appendingPathComponent(name ?? fixture))
  }

  func write(_ text: String, to name: String) throws {
    try Data(text.utf8).write(to: folder.appendingPathComponent(name))
  }

  func append(_ text: String, to name: String) throws {
    let handle = try FileHandle(forWritingTo: folder.appendingPathComponent(name))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try handle.close()
  }

  func count(_ sql: String) async throws -> Int {
    try await database.read { db in try Int.fetchOne(db, sql: sql) ?? -1 }
  }

  func file(_ name: String) async throws -> IngestFileRecord? {
    // The service keys files by the path it listed (`/private/var/…` for a temp folder), so match by name.
    try await repository.loadIngestFiles().first { URL(fileURLWithPath: $0.path).lastPathComponent == name }
  }

  func records(_ evt: Evt) async -> [LogRecord] { await store.records(evt) }

  /// For `eventually`: the file's state, or nil (and a recorded issue) when it cannot be read.
  func state(_ name: String) async -> String? {
    do {
      return try await file(name)?.state
    } catch {
      Issue.record("ingest_file not read: \(error)")
      return nil
    }
  }

  /// For `eventually`: the number of `harness_event` rows.
  func events() async -> Int {
    do {
      return try await count("SELECT count(*) FROM harness_event")
    } catch {
      Issue.record("harness_event not read: \(error)")
      return -1
    }
  }

  /// One v1 DeepSeek line.
  static func line(_ id: String, app: String = "weather-collector", ts: String = "2026-11-10T10:00:00Z",
                   prompt: Int = 1000, hint: String = "a9f2") -> String {
    "{\"v\":1,\"ts\":\"\(ts)\",\"provider\":\"deepseek\",\"app\":\"\(app)\",\"key_hint\":\"\(hint)\"," +
      "\"request_id\":\"\(id)\",\"model\":\"deepseek-chat\",\"usage\":{\"prompt_tokens\":\(prompt)," +
      "\"completion_tokens\":200,\"prompt_cache_hit_tokens\":600},\"status\":\"ok\"}\n"
  }
}
