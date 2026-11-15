import Foundation
import GRDB

/// `band_state` rows (03), one per account after its first evaluation (14 § Stage 5.3 step 2).
public protocol BandRepository: Sendable {
  /// Inserts or replaces the account's row: band, `since` and `inputs_json` in one statement, so a band never
  /// changes without its inputs (04 V6).
  func recordBand(_ state: BandStateRecord) async throws
  /// Every `band_state` row (04 startup step 8: the glyph's state before the first polls).
  func fetchBandStates() async throws -> [BandStateRecord]
}

extension GRDBRepository {
  public func recordBand(_ state: BandStateRecord) async throws {
    try await database.write("recordBand") { db in
      try state.insert(db, onConflict: .replace)
    }
  }

  public func fetchBandStates() async throws -> [BandStateRecord] {
    try await database.read { db in try BandStateRecord.order(Column("account_id")).fetchAll(db) }
  }
}
