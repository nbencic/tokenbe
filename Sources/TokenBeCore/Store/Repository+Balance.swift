import Foundation
import GRDB

/// `balance_snapshot` rows (03), written by the `balance` poll of direct providers (02; 14 § Stage 6.1).
public protocol BalanceRepository: Sendable {
  /// One poll's snapshots (one per currency), in one transaction. A snapshot whose `(account_id, ts, currency)`
  /// exists replaces it.
  func insertBalanceSnapshots(_ snapshots: [BalanceSnapshotRecord]) async throws
  /// Oldest first, then by currency.
  func fetchBalanceSnapshots(accountID: String) async throws -> [BalanceSnapshotRecord]
}

extension GRDBRepository {
  public func insertBalanceSnapshots(_ snapshots: [BalanceSnapshotRecord]) async throws {
    try await database.write("insertBalanceSnapshots") { db in
      for snapshot in snapshots {
        try snapshot.save(db)
      }
    }
  }

  public func fetchBalanceSnapshots(accountID: String) async throws -> [BalanceSnapshotRecord] {
    try await database.read { db in
      try BalanceSnapshotRecord.filter(Column("account_id") == accountID).order(Column("ts"), Column("currency"))
        .fetchAll(db)
    }
  }
}
