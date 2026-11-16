import Foundation
import GRDB

/// One accepted line, ready to store (06 § processLine).
public struct IngestLine: Sendable {
  public var line: HarnessLine
  /// 1-based, among the file's non-empty lines (`harness_event.source_line`).
  public var lineNo: Int64
  /// The line's cost: the price book's estimate, or OpenRouter's `cost_cents` (06); nil when unpriced.
  public var estCents: Int64?
  /// `ts` > ingestion time + 5 min (06 clock skew): stored with `future_ts = 1`.
  public var futureTs: Bool
  /// `ts` older than the hourly retention horizon (06): stored, no bucket.
  public var tooOld: Bool

  public init(line: HarnessLine, lineNo: Int64, estCents: Int64?, futureTs: Bool = false, tooOld: Bool = false) {
    self.line = line
    self.lineNo = lineNo
    self.estCents = estCents
    self.futureTs = futureTs
    self.tooOld = tooOld
  }
}

/// One read of one file, applied in ONE transaction (04 V7): the lines' `harness_event` rows, their apps, bindings
/// and `usage_bucket(source = 'harness')` rows, and the file's offset, size, mtime, state and counters.
public struct IngestBatch: Sendable {
  /// The file's new position and state. Its counters are ignored: the transaction adds this batch's counts.
  public var file: IngestFileRecord
  public var lines: [IngestLine]
  /// Lines rejected in this batch (`lines_bad` += this).
  public var rejected: Int64
  /// A new file at a known path (inode changed, truncated): the counters restart from this batch.
  public var resetCounters: Bool
  public var ingestedAt: String
  /// Prices a harness bucket from its summed classes, as `repriceUsage` does (05).
  public var price: @Sendable (UsageBucketRecord, ProviderID) -> UsageBucketRecord

  public init(file: IngestFileRecord, lines: [IngestLine] = [], rejected: Int64 = 0, resetCounters: Bool = false,
              ingestedAt: String,
              price: @escaping @Sendable (UsageBucketRecord, ProviderID) -> UsageBucketRecord = { row, _ in row }) {
    self.file = file
    self.lines = lines
    self.rejected = rejected
    self.resetCounters = resetCounters
    self.ingestedAt = ingestedAt
    self.price = price
  }
}

/// What a batch did, for the caller's log records (07 `ingest.*`).
public struct IngestBatchResult: Sendable, Equatable {
  public var inserted = 0
  /// Request ids already stored with the same usage (`ingest.duplicate`, debug).
  public var duplicates: [String] = []
  /// Request ids already stored with a different usage; the first wins (`ingest.duplicate_conflict`).
  public var conflicts: [String] = []
  /// `app` rows created from new harness tags (`ingest.app_created`), as (tag, provider).
  public var appsCreated: [AppCreated] = []
  /// Lines whose key hint matched more than one key (`ingest.key_hint_ambiguous`).
  public var ambiguousHints: [Int64] = []
  /// Lines stored for a provider with no account (O-12).
  public var withoutAccount = 0

  public struct AppCreated: Sendable, Equatable {
    public var app: String
    public var provider: String
  }

  public init() {}
}

/// `ingest_file` and `harness_event` (03; 14 § 2.1 step 5: `loadIngestFiles`, `applyIngestBatch`).
public protocol IngestRepository: Sendable {
  /// Every `ingest_file` row, by path.
  func loadIngestFiles() async throws -> [IngestFileRecord]
  /// Applies the batch in one transaction (V7); a failure rolls all of it back.
  func applyIngestBatch(_ batch: IngestBatch) async throws -> IngestBatchResult
}

extension GRDBRepository {
  public func loadIngestFiles() async throws -> [IngestFileRecord] {
    try await database.read { db in try IngestFileRecord.order(Column("path")).fetchAll(db) }
  }

  public func applyIngestBatch(_ batch: IngestBatch) async throws -> IngestBatchResult {
    try await database.write("applyIngestBatch") { db in
      var result = IngestBatchResult()
      var accounts: [String: String?] = [:]
      for item in batch.lines {
        let provider = item.line.provider.rawValue
        if accounts[provider] == nil {
          accounts[provider] = .some(try String.fetchOne(db, sql: "SELECT id FROM account WHERE provider = ?",
                                                         arguments: [provider]))
        }
        try Self.store(item, account: accounts[provider] ?? nil, batch: batch, db: db, result: &result)
      }
      try Self.saveFile(batch, dup: Int64(result.duplicates.count + result.conflicts.count),
                        inserted: Int64(result.inserted), db: db)
      return result
    }
  }

  /// 06 processLine, after parsing: dedup, the key hint, app and binding, the bucket.
  static func store(_ item: IngestLine, account: String?, batch: IngestBatch, db: GRDB.Database,
                    result: inout IngestBatchResult) throws {
    let line = item.line
    var keyID: String?
    if let account, let hint = line.keyHint {
      let keys = try String.fetchAll(db, sql: """
        SELECT provider_key_id FROM provider_key WHERE account_id = ? AND redacted IS NOT NULL AND substr(redacted, -4) = ?
        """, arguments: [account, hint])
      if keys.count == 1 { keyID = keys[0] } else if keys.count > 1 { result.ambiguousHints.append(item.lineNo) }
    }
    try db.execute(sql: """
      INSERT OR IGNORE INTO harness_event (provider, request_id, account_id, app_tag, provider_key_id, key_hint, ts,
        future_ts, model, status, usage_json, classes_json, est_cost_cents, source_file, source_line, ingested_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """, arguments: [line.provider.rawValue, line.requestID, account, line.app, keyID, line.keyHint,
                       DBTime.string(line.date), item.futureTs, line.model, line.succeeded ? 1 : 0, line.usageJSON,
                       line.classesJSON, item.estCents, batch.file.path, item.lineNo, batch.ingestedAt])
    guard db.changesCount == 1 else {
      let stored = try String.fetchOne(db, sql: "SELECT usage_json FROM harness_event WHERE provider = ? AND request_id = ?",
                                       arguments: [line.provider.rawValue, line.requestID])
      if stored == line.usageJSON { result.duplicates.append(line.requestID) } else { result.conflicts.append(line.requestID) }
      return
    }
    result.inserted += 1
    let app = try AppRecord.fetchOne(db, sql: "SELECT * FROM app WHERE lower(name) = ?", arguments: [line.app])
      ?? createApp(line.app, provider: line.provider.rawValue, at: batch.ingestedAt, db: db, result: &result)
    guard let account else {
      result.withoutAccount += 1
      return
    }
    try db.execute(sql: """
      INSERT OR IGNORE INTO app_binding (app_id, account_id, kind, value) VALUES (?, ?, 'harness_tag', ?)
      """, arguments: [app.id, account, app.name])
    // An error line without usable usage still counts as a request (06 `status`).
    guard !item.tooOld, let classes = line.classes ?? (line.succeeded ? nil : TokenClasses(requests: 1)) else { return }
    try upsertBucket(classes, line: line, owner: (account, keyID), batch: batch, db: db)
  }

  static func createApp(_ tag: String, provider: String, at time: String, db: GRDB.Database,
                        result: inout IngestBatchResult) throws -> AppRecord {
    let app = AppRecord(id: UUIDv7.make(), name: tag, displayName: tag, createdAt: time, isAuto: true)
    try app.insert(db)
    result.appsCreated.append(.init(app: tag, provider: provider))
    return app
  }

  /// 06: `usage_bucket(source = 'harness', bucket_width = '1h', bucket_start = floor(ts to the UTC hour), model,
  /// provider_key_id, service_tier = 'standard')`, its classes summed and priced as a whole (Q-049).
  static func upsertBucket(_ classes: TokenClasses, line: HarnessLine, owner: (account: String, keyID: String?),
                           batch: IngestBatch, db: GRDB.Database) throws {
    let (account, keyID) = owner
    let hour = Date(timeIntervalSince1970: (line.date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    let key: [String: (any DatabaseValueConvertible)?] = [
      "account_id": account, "bucket_start": DBTime.string(hour), "bucket_width": "1h", "model": line.model,
      "provider_key_id": keyID ?? "", "service_tier": "standard", "source": "harness"
    ]
    var row = try UsageBucketRecord.fetchOne(db, key: key) ?? UsageBucketRecord(
      accountId: account, bucketStart: DBTime.string(hour), bucketWidth: "1h", model: line.model,
      providerKeyId: keyID ?? "", serviceTier: "standard", source: "harness", inputUncached: 0, cacheWrite5m: 0,
      cacheWrite1h: 0, cacheRead: 0, output: 0, reasoning: 0, requests: 0, estCostCents: nil, unpriced: false,
      provisional: false, fetchedAt: batch.ingestedAt
    )
    row.inputUncached += classes.inputUncached
    row.cacheWrite5m += classes.cacheWrite5m
    row.cacheWrite1h += classes.cacheWrite1h
    row.cacheRead += classes.cacheRead
    row.output += classes.output
    row.reasoning += classes.reasoning
    row.requests += classes.requests
    row.fetchedAt = batch.ingestedAt
    try batch.price(row, line.provider).insert(db, onConflict: .replace)
  }

  static func saveFile(_ batch: IngestBatch, dup: Int64, inserted: Int64, db: GRDB.Database) throws {
    let file = batch.file
    // A new file at a known path starts its counters from this batch.
    let prior = { (column: String) in batch.resetCounters ? "0" : "ingest_file.\(column)" }
    try db.execute(sql: """
      INSERT INTO ingest_file (path, inode, offset, last_size, last_mtime, state, lines_ok, lines_bad, lines_dup)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (path) DO UPDATE SET inode = excluded.inode, offset = excluded.offset,
        last_size = excluded.last_size, last_mtime = excluded.last_mtime, state = excluded.state,
        lines_ok = \(prior("lines_ok")) + excluded.lines_ok, lines_bad = \(prior("lines_bad")) + excluded.lines_bad,
        lines_dup = \(prior("lines_dup")) + excluded.lines_dup
      """, arguments: [file.path, file.inode, file.offset, file.lastSize, file.lastMtime, file.state, inserted,
                       batch.rejected, dup])
  }
}
