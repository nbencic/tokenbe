import Foundation
import GRDB

/// `price_snapshot` and `price_override` rows (03; 14 § Stage 5.1). One snapshot is current; 03 keeps it and the
/// previous three.
public protocol PriceRepository: Sendable {
  /// The `is_current` snapshot, if any.
  func fetchCurrentPriceSnapshot() async throws -> PriceSnapshotRecord?
  /// Every snapshot's version, newest `fetched_at` first (the blobs are not read).
  func fetchPriceSnapshotVersions() async throws -> [String]
  /// In one transaction: the new row becomes the only current one. A row with the same version (a second fetch on
  /// the same day, Q-038) is replaced.
  func insertCurrentPriceSnapshot(_ snapshot: PriceSnapshotRecord) async throws
  /// A check that found the feed unchanged (HTTP 304 or the same sha256): `fetched_at`, and the ETag when one came,
  /// move to the check, so staleness measures the last successful check (Q-038).
  func touchPriceSnapshot(version: String, fetchedAt: String, etag: String?) async throws
  /// Deletes all but the `keep` newest snapshots; the current one is never deleted. Returns the rows deleted.
  @discardableResult
  func prunePriceSnapshots(keep: Int) async throws -> Int
  /// By model.
  func fetchPriceOverrides() async throws -> [PriceOverrideRecord]
  /// Inserts or replaces the model's override.
  func upsertPriceOverride(_ override: PriceOverrideRecord) async throws
  /// Throws `StoreError.notFound` when the model has no override.
  func deletePriceOverride(model: String) async throws
  /// Returns the rows deleted.
  @discardableResult
  func deleteAllPriceOverrides() async throws -> Int
}

extension GRDBRepository {
  public func fetchCurrentPriceSnapshot() async throws -> PriceSnapshotRecord? {
    try await database.read { db in
      try PriceSnapshotRecord.filter(Column("is_current") == true).fetchOne(db)
    }
  }

  public func fetchPriceSnapshotVersions() async throws -> [String] {
    try await database.read { db in
      try String.fetchAll(db, sql: "SELECT version FROM price_snapshot ORDER BY fetched_at DESC, version DESC")
    }
  }

  public func insertCurrentPriceSnapshot(_ snapshot: PriceSnapshotRecord) async throws {
    try await database.write("insertCurrentPriceSnapshot") { db in
      try db.execute(sql: "UPDATE price_snapshot SET is_current = 0 WHERE is_current = 1")
      var row = snapshot
      row.isCurrent = true
      try row.save(db)
    }
  }

  public func touchPriceSnapshot(version: String, fetchedAt: String, etag: String?) async throws {
    try await database.write("touchPriceSnapshot") { db in
      try db.execute(sql: "UPDATE price_snapshot SET fetched_at = ?, etag = coalesce(?, etag) WHERE version = ?",
                     arguments: [fetchedAt, etag, version])
    }
  }

  public func prunePriceSnapshots(keep: Int) async throws -> Int {
    try await database.write("prunePriceSnapshots") { db in
      try db.execute(sql: """
        DELETE FROM price_snapshot WHERE is_current = 0 AND version NOT IN (
          SELECT version FROM price_snapshot ORDER BY is_current DESC, fetched_at DESC, version DESC LIMIT ?)
        """, arguments: [max(keep, 1)])
      return db.changesCount
    }
  }

  public func fetchPriceOverrides() async throws -> [PriceOverrideRecord] {
    try await database.read { db in try PriceOverrideRecord.order(Column("model")).fetchAll(db) }
  }

  public func upsertPriceOverride(_ override: PriceOverrideRecord) async throws {
    try await database.write("upsertPriceOverride") { db in try override.save(db) }
  }

  public func deletePriceOverride(model: String) async throws {
    let deleted = try await database.write("deletePriceOverride") { db in
      try PriceOverrideRecord.deleteOne(db, key: model)
    }
    guard deleted else { throw StoreError.notFound(model) }
  }

  public func deleteAllPriceOverrides() async throws -> Int {
    try await database.write("deleteAllPriceOverrides") { db in try PriceOverrideRecord.deleteAll(db) }
  }
}
