import Foundation
import GRDB

/// The tables 03 § Durability exports, in the document's order, with the primary key each one is sorted by.
/// `poll_state` and `ingest_file` are excluded (O-5), and so are the tables 03's document does not list:
/// `harness_event`, `band_state`, `price_snapshot` and `schema_version` (Q-056).
public enum ExportedTable: String, CaseIterable, Sendable {
  case account, providerKey = "provider_key", app, appBinding = "app_binding", usageBucket = "usage_bucket"
  case costBucket = "cost_bucket", balanceSnapshot = "balance_snapshot", ledgerEvent = "ledger_event"
  case priceOverride = "price_override"

  /// The SQL table name, which is also the CSV file's name (`account.csv`).
  public var table: String { rawValue }

  /// The JSON document's key for the table (03: `accounts`, `provider_keys`, …).
  public var documentKey: String { rawValue + "s" }

  /// The primary key, so every export lists its rows in the same order.
  var orderBy: String {
    switch self {
    case .account, .app, .ledgerEvent: "id"
    case .providerKey: "account_id, provider_key_id"
    case .appBinding: "account_id, kind, value"
    case .usageBucket: "account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source"
    case .costBucket: "account_id, day, group_kind, group_key"
    case .balanceSnapshot: "account_id, ts, currency"
    case .priceOverride: "model"
    }
  }
}

/// 03 § Durability's JSON document: `schema_version`, `exported_at`, then one array per exported table. The records'
/// keys are their column names. A NULL column is left out of its object and reads back as NULL (Q-056).
public struct ExportDocument: Codable, Sendable, Equatable {
  public var schemaVersion: Int
  public var exportedAt: String
  public var accounts: [AccountRecord]
  public var providerKeys: [ProviderKeyRecord]
  public var apps: [AppRecord]
  public var appBindings: [AppBindingRecord]
  public var usageBuckets: [UsageBucketRecord]
  public var costBuckets: [CostBucketRecord]
  public var balanceSnapshots: [BalanceSnapshotRecord]
  public var ledgerEvents: [LedgerEventRecord]
  public var priceOverrides: [PriceOverrideRecord]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version", exportedAt = "exported_at", accounts, providerKeys = "provider_keys", apps
    case appBindings = "app_bindings", usageBuckets = "usage_buckets", costBuckets = "cost_buckets"
    case balanceSnapshots = "balance_snapshots", ledgerEvents = "ledger_events", priceOverrides = "price_overrides"
  }

  public init(schemaVersion: Int, exportedAt: String, accounts: [AccountRecord] = [],
              providerKeys: [ProviderKeyRecord] = [], apps: [AppRecord] = [], appBindings: [AppBindingRecord] = [],
              usageBuckets: [UsageBucketRecord] = [], costBuckets: [CostBucketRecord] = [],
              balanceSnapshots: [BalanceSnapshotRecord] = [], ledgerEvents: [LedgerEventRecord] = [],
              priceOverrides: [PriceOverrideRecord] = []) {
    self.schemaVersion = schemaVersion
    self.exportedAt = exportedAt
    self.accounts = accounts
    self.providerKeys = providerKeys
    self.apps = apps
    self.appBindings = appBindings
    self.usageBuckets = usageBuckets
    self.costBuckets = costBuckets
    self.balanceSnapshots = balanceSnapshots
    self.ledgerEvents = ledgerEvents
    self.priceOverrides = priceOverrides
  }

  /// Rows per exported table, in the document's order.
  public var counts: [ExportedTable: Int] {
    [.account: accounts.count, .providerKey: providerKeys.count, .app: apps.count, .appBinding: appBindings.count,
     .usageBucket: usageBuckets.count, .costBucket: costBuckets.count, .balanceSnapshot: balanceSnapshots.count,
     .ledgerEvent: ledgerEvents.count, .priceOverride: priceOverrides.count]
  }

  /// Σ rows over the exported tables (`db.export` / `db.import` `rows`).
  public var rows: Int { counts.values.reduce(0, +) }
}

/// Why an import was refused before anything was written (O-17; 07 `db.import_failed`).
public enum ImportRefusal: LocalizedError, Sendable, Equatable, CustomStringConvertible {
  /// The database already holds an account, a price override or an app besides the `Unassigned` seed (O-17).
  case notEmpty
  /// The document was written by another schema version; V1 does not convert (03 § Migrations).
  case schemaVersion(found: Int, expected: Int)

  public var description: String {
    switch self {
    case .notEmpty: "not_empty"
    case .schemaVersion(let found, let expected): "schema_version \(found), expected \(expected)"
    }
  }

  /// The log's `err.desc` (07).
  public var errorDescription: String? { description }
}

/// 03 § Durability export and import (14 § Stage 9.2), and the raw tables for `Export CSV (all tables)…`.
public protocol DataTransferRepository: Sendable {
  /// Every exported table in one read, each sorted by its primary key.
  func exportDocument(exportedAt: String) async throws -> ExportDocument
  /// Each exported table as its column names and its values as text (NULL → empty), sorted by primary key.
  func exportTables() async throws -> [(table: ExportedTable, csv: CSVTable)]
  /// In ONE transaction: refuses a database that is not empty or a document of another schema version
  /// (`ImportRefusal`), then inserts every row. Each account gets its four `poll_state` rows, as when it is created
  /// (03); the `Unassigned` seed app is already there. Returns the rows inserted.
  func importDocument(_ document: ExportDocument) async throws -> Int
}

extension GRDBRepository {
  public func exportDocument(exportedAt: String) async throws -> ExportDocument {
    try await database.read { db in
      func rows<R: FetchableRecord & TableRecord>(_ type: R.Type, _ table: ExportedTable) throws -> [R] {
        try R.fetchAll(db, sql: "SELECT * FROM \(table.table) ORDER BY \(table.orderBy)")
      }
      return ExportDocument(
        schemaVersion: try Migrator.currentVersion(db), exportedAt: exportedAt,
        accounts: try rows(AccountRecord.self, .account),
        providerKeys: try rows(ProviderKeyRecord.self, .providerKey).map { key in
          var key = key
          key.redacted = Self.exportedHint(key.redacted)
          return key
        },
        apps: try rows(AppRecord.self, .app), appBindings: try rows(AppBindingRecord.self, .appBinding),
        usageBuckets: try rows(UsageBucketRecord.self, .usageBucket),
        costBuckets: try rows(CostBucketRecord.self, .costBucket),
        balanceSnapshots: try rows(BalanceSnapshotRecord.self, .balanceSnapshot),
        ledgerEvents: try rows(LedgerEventRecord.self, .ledgerEvent),
        priceOverrides: try rows(PriceOverrideRecord.self, .priceOverride))
    }
  }

  public func exportTables() async throws -> [(table: ExportedTable, csv: CSVTable)] {
    try await database.read { db in
      try ExportedTable.allCases.map { table in
        let header = try db.columns(in: table.table).map(\.name)
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(table.table) ORDER BY \(table.orderBy)").map { row in
          header.map { column in
            let value = row[column] as DatabaseValue
            return table == .providerKey && column == "redacted"
              ? Self.exportedHint(String.fromDatabaseValue(value)) ?? "" : Self.text(value)
          }
        }
        return (table, CSVTable(header: header, rows: rows))
      }
    }
  }

  /// `provider_key.redacted` leaves the app as its key hint only, `…` and the last 4 characters (03; R13): the hint
  /// is all TokenBe reads from it (the Accounts tab, ingest's key-hint match), and a provider's redacted value can
  /// carry the key's prefix (`sk-…`), which no export may contain (A9, E2E-7; Q-056).
  static func exportedHint(_ redacted: String?) -> String? {
    redacted.map { "\u{2026}" + String($0.suffix(4)) }
  }

  /// A column's value as CSV text: NULL is empty, a blob is Base64 (no exported table has one today).
  static func text(_ value: DatabaseValue) -> String {
    switch value.storage {
    case .null: ""
    case .int64(let number): String(number)
    case .double(let number): String(number)
    case .string(let string): string
    case .blob(let data): data.base64EncodedString()
    }
  }

  public func importDocument(_ document: ExportDocument) async throws -> Int {
    try await database.write("importDocument") { db in
      // A document from this schema or an earlier one imports: no migration since 001 changes an exported column
      // (002 only widens account.provider's CHECK, Q-063). A newer document is refused.
      let expected = try Migrator.currentVersion(db)
      guard (1...expected).contains(document.schemaVersion) else {
        throw ImportRefusal.schemaVersion(found: document.schemaVersion, expected: expected)
      }
      let occupied = try Int.fetchOne(db, sql: """
        SELECT (SELECT COUNT(*) FROM account) + (SELECT COUNT(*) FROM price_override)
          + (SELECT COUNT(*) FROM app WHERE id <> ?)
        """, arguments: [Attribution.unassignedID]) ?? 0
      guard occupied == 0 else { throw ImportRefusal.notEmpty }
      try Self.insert(document, db: db)
      return document.rows
    }
  }

  /// Parents before children (foreign keys): accounts, then their keys; apps, then bindings; then the rows.
  static func insert(_ document: ExportDocument, db: GRDB.Database) throws {
    for account in document.accounts {
      try account.insert(db)
      try Self.seedPollStates(accountID: account.id, db: db)
    }
    for key in document.providerKeys { try key.insert(db) }
    for app in document.apps where app.id != Attribution.unassignedID { try app.insert(db) }
    for binding in document.appBindings { try binding.insert(db) }
    for bucket in document.usageBuckets { try bucket.insert(db) }
    for cost in document.costBuckets { try cost.insert(db) }
    for snapshot in document.balanceSnapshots { try snapshot.insert(db) }
    for event in document.ledgerEvents { try event.insert(db) }
    for override in document.priceOverrides { try override.insert(db) }
  }

  /// 03: an account's four `poll_state` rows (`usage`, `cost`, `balance`, `keys`), seeded with the account.
  static func seedPollStates(accountID: String, db: GRDB.Database) throws {
    for job in Job.allCases {
      try db.execute(sql: "INSERT INTO poll_state (account_id, job) VALUES (?, ?)", arguments: [accountID, job.rawValue])
    }
  }
}
