import Foundation
import GRDB

/// `ledger_event` rows (03). Stage 3.5 inserts only: onboarding's optional anchor (14 § Stage 3.5). Reads, top-ups
/// and the ledger math arrive with 5.3.
public protocol LedgerRepository: Sendable {
  /// Throws `StoreError.duplicate` for an existing id.
  func insertLedgerEvent(_ event: LedgerEventRecord) async throws
}

extension GRDBRepository {
  public func insertLedgerEvent(_ event: LedgerEventRecord) async throws {
    try await database.write("insertLedgerEvent") { db in
      try Self.translatingConstraints(event.id) { try event.insert(db) }
    }
  }
}
