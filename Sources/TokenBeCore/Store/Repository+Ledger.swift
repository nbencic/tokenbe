import Foundation
import GRDB

/// `ledger_event` rows (03): onboarding's anchor (3.5); anchors, top-ups and deleting user rows from the account
/// page (5.3). The ledger is read through `observeSummaryInputs`.
public protocol LedgerRepository: Sendable {
  /// Throws `StoreError.duplicate` for an existing id.
  func insertLedgerEvent(_ event: LedgerEventRecord) async throws
  /// Deletes the row only when `source = 'user'` (R7: system rows are never deleted); true when a row went.
  func deleteUserLedgerEvent(id: String) async throws -> Bool
}

extension GRDBRepository {
  public func insertLedgerEvent(_ event: LedgerEventRecord) async throws {
    try await database.write("insertLedgerEvent") { db in
      try Self.translatingConstraints(event.id) { try event.insert(db) }
    }
  }

  public func deleteUserLedgerEvent(id: String) async throws -> Bool {
    try await database.write("deleteUserLedgerEvent") { db in
      try db.execute(sql: "DELETE FROM ledger_event WHERE id = ? AND source = 'user'", arguments: [id])
      return db.changesCount > 0
    }
  }
}
