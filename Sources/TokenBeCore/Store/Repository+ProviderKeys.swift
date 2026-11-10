import Foundation
import GRDB

/// `provider_key` rows (03): what the keys poll and the probe discover.
public protocol ProviderKeyRepository: Sendable {
  /// Inserts new keys and refreshes known ones (`name`, `redacted`, `project_id`, `workspace_id`, `status = 'active'`,
  /// `last_seen_at`); `first_seen_at` is kept. Keys missing from the list are left as they are (Q-029). One
  /// transaction.
  func upsertProviderKeys(accountID: String, keys: [DiscoveredKey], seenAt: Date) async throws
  /// By `provider_key_id`.
  func fetchProviderKeys(accountID: String) async throws -> [ProviderKeyRecord]
}

extension GRDBRepository {
  public func upsertProviderKeys(accountID: String, keys: [DiscoveredKey], seenAt: Date) async throws {
    let seen = DBTime.string(seenAt)
    try await database.write("upsertProviderKeys") { db in
      for key in keys {
        try db.execute(sql: """
          INSERT INTO provider_key
            (account_id, provider_key_id, name, redacted, project_id, workspace_id, status, first_seen_at, last_seen_at)
          VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)
          ON CONFLICT (account_id, provider_key_id) DO UPDATE SET
            name = excluded.name, redacted = excluded.redacted, project_id = excluded.project_id,
            workspace_id = excluded.workspace_id, status = 'active', last_seen_at = excluded.last_seen_at
          """, arguments: [accountID, key.providerKeyID, key.name, key.redacted, key.projectID, key.workspaceID,
                           seen, seen])
      }
    }
  }

  public func fetchProviderKeys(accountID: String) async throws -> [ProviderKeyRecord] {
    try await database.read { db in
      try ProviderKeyRecord.filter(Column("account_id") == accountID).order(Column("provider_key_id")).fetchAll(db)
    }
  }
}
