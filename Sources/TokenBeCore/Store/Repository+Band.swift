import Foundation
import GRDB

/// `band_state` rows (03), one per account after its first evaluation (14 § Stage 5.3 step 2).
public protocol BandRepository: Sendable {
  /// Inserts or replaces the account's row: band, `since` and `inputs_json` in one statement, so a band never
  /// changes without its inputs (04 V6).
  func recordBand(_ state: BandStateRecord) async throws
}

extension GRDBRepository {
  public func recordBand(_ state: BandStateRecord) async throws {
    try await database.write("recordBand") { db in
      try state.insert(db, onConflict: .replace)
    }
  }
}
