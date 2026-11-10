import Foundation
import GRDB
@testable import TokenBeCore

/// Builds `Tests/Fixtures/db/schema_v1.sqlite` (11, 14 § Stage 2.1 step 8): migration 001 plus one representative
/// row in every table, with fixed timestamps so the committed file is reproducible. `corrupt.sqlite` is its first
/// 4 KiB. Regenerate with `TOKENBE_WRITE_FIXTURES=1 swift test --filter FixtureDBTests`.
enum FixtureDBBuilder {
  static let stamp = "2026-01-15T09:30:00.000Z"
  /// OpenAI's 02 capabilities, as `Capabilities.json()` stores them (`CapabilitiesTests.fixtureRow` keeps the two equal).
  static let capabilities = Capabilities(usage: true, cost: true, balance: false, perKeyUsage: true, keyNames: true,
                                         balanceModeDefault: .anchored, usageLag: .seconds(3600), currencyHint: .usd)
  static let capabilitiesJSON = #"{"balance":false,"balance_mode_default":"anchored","cost":true,"#
    + #""currency_hint":"USD","key_names":true,"per_key_usage":true,"usage":true,"usage_lag_s":3600}"#
  static let accountID = "0190f0a0-0000-7000-8000-000000000001"

  static func account(id: String = accountID, provider: String = "openai", label: String = "OpenAI",
                      createdAt: String = stamp) -> AccountRecord {
    AccountRecord(
      id: id, provider: provider, label: label, keychainRef: "tokenbe.\(provider)", balanceMode: "anchored",
      currency: "USD", capabilities: capabilitiesJSON,
      orgId: "org-fixture", orgName: "Fixture Org", autoReloadEnabled: false, autoReloadToCents: nil,
      autoReloadBelowCents: nil, paused: false, intervalOverrideJson: nil, createdAt: createdAt
    )
  }

  /// One row per table besides the seeds; every column of every record type is written.
  static func representativeRows(_ db: GRDB.Database) throws {
    let acct = accountID
    try account().insert(db)
    for job in Job.allCases {
      try PollStateRecord(
        accountId: acct, job: job.rawValue, lastAttemptAt: stamp, lastSuccessAt: stamp, lastErrorClass: nil,
        lastErrorMessage: nil, consecutiveFailures: 0, circuitOpenUntil: nil, cursor: nil, lastRaw: Data("{}".utf8)
      ).insert(db)
    }
    try keysAndApps(db)
    try usageAndMoney(db)
    try pricesAndState(db)
  }

  private static func keysAndApps(_ db: GRDB.Database) throws {
    let acct = accountID
    try ProviderKeyRecord(
      accountId: acct, providerKeyId: "key_fixture1", name: "ci", redacted: "sk-…abcd", projectId: "proj_1",
      workspaceId: nil, status: "active", firstSeenAt: stamp, lastSeenAt: stamp
    ).insert(db)
    try AppRecord(id: "app_fixture", name: "my-agent", displayName: "My Agent", createdAt: stamp, isAuto: false)
      .insert(db)
    try AppBindingRecord(appId: "app_fixture", accountId: acct, kind: "provider_key", value: "key_fixture1").insert(db)
  }

  private static func usageAndMoney(_ db: GRDB.Database) throws {
    let acct = accountID
    try UsageBucketRecord(
      accountId: acct, bucketStart: "2026-01-15T09:00:00.000Z", bucketWidth: "1h", model: "gpt-5",
      providerKeyId: "key_fixture1", serviceTier: "", source: "provider", inputUncached: 1200, cacheWrite5m: 0,
      cacheWrite1h: 0, cacheRead: 300, output: 450, reasoning: 120, requests: 3, estCostCents: 2, unpriced: false,
      provisional: true, fetchedAt: stamp
    ).insert(db)
    try CostBucketRecord(
      accountId: acct, day: "2026-01-15", groupKind: "total", groupKey: "", amountCents: 125, currency: "USD",
      provisional: true, fetchedAt: stamp
    ).insert(db)
    try BalanceSnapshotRecord(
      accountId: acct, ts: stamp, currency: "USD", amountCents: 4_875, grantedCents: nil, toppedUpCents: 5_000,
      isAvailable: true
    ).insert(db)
    try HarnessEventRecord(
      provider: "openai", requestId: "req_fixture1", accountId: acct, appTag: "my-agent",
      providerKeyId: "key_fixture1", keyHint: "abcd", ts: stamp, futureTs: false, model: "gpt-5", status: 1,
      usageJson: #"{"input_tokens":10,"output_tokens":5}"#, classesJson: nil, estCostCents: 1,
      sourceFile: "/tmp/harness/2026-01-15.jsonl", sourceLine: 1, ingestedAt: stamp
    ).insert(db)
    try IngestFileRecord(
      path: "/tmp/harness/2026-01-15.jsonl", inode: 42, offset: 128, lastSize: 128, lastMtime: stamp,
      state: "active", linesOk: 1, linesBad: 0, linesDup: 0
    ).insert(db)
    try LedgerEventRecord(
      id: "0190f0a0-0000-7000-8000-0000000000aa", accountId: acct, ts: stamp, kind: "anchor", amountCents: 5_000,
      currency: "USD", note: "starting balance", source: "user"
    ).insert(db)
  }

  private static func pricesAndState(_ db: GRDB.Database) throws {
    let acct = accountID
    try PriceSnapshotRecord(
      version: "bundled-0.1.0", fetchedAt: stamp, etag: nil, sha256: String(repeating: "0", count: 64),
      json: Data(#"{"models":{}}"#.utf8), isCurrent: true
    ).insert(db)
    try PriceOverrideRecord(model: "gpt-5", json: #"{"input":1.25,"output":10}"#, updatedAt: stamp).insert(db)
    try BandStateRecord(
      accountId: acct, band: "healthy", since: stamp,
      inputsJson: #"{"remaining":4875,"burn_7d":100,"burn_today":20,"floor":0}"#
    ).insert(db)
  }

  /// Builds the fixture in `directory` and returns a single-file copy (WAL checkpointed, `journal_mode=DELETE`).
  static func build(in directory: URL) async throws -> URL {
    // A private pipeline: only LogFacadeTests may log through the process-wide `Log`.
    let quiet = LogPipeline(sinks: [], version: "test")
    let opened = try await DatabaseOpener.open(directory: directory, logPipeline: quiet)
    try await opened.database.write("fixture") { db in
      try db.execute(sql: "UPDATE schema_version SET applied_at = ?", arguments: [stamp])
      try db.execute(sql: "UPDATE app SET created_at = ? WHERE id = 'app_unassigned'", arguments: [stamp])
      try representativeRows(db)
    }
    let output = directory.appendingPathComponent("schema_v1.sqlite")
    try await opened.database.pool.writeWithoutTransaction { db in
      try db.execute(sql: "VACUUM INTO ?", arguments: [output.path])
    }
    try opened.database.close()
    let single = try DatabaseQueue(path: output.path)
    try await single.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA journal_mode = DELETE") }
    try single.close()
    return output
  }

  /// `Tests/Fixtures/db` in the source tree (for regeneration), and its copy inside the test bundle (for reading).
  static func sourceDirectory() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/db", isDirectory: true)
  }

  static func bundled(_ name: String) throws -> URL {
    guard let root = Bundle.module.resourceURL else { throw StoreError.notFound("test bundle resources") }
    return root.appendingPathComponent("Fixtures/db/\(name)")
  }

  /// Copies a fixture into `directory` as `tokenbe.sqlite` (or `as`), never opening it in place.
  @discardableResult
  static func install(_ name: String, into directory: URL, as target: String = AppDatabase.fileName) throws -> URL {
    let destination = directory.appendingPathComponent(target)
    try FileManager.default.copyItem(at: try bundled(name), to: destination)
    return destination
  }
}
