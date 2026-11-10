import Foundation
import GRDB

/// `Repository` on `tokenbe.sqlite`. Writes are serialized by the actor and the pool's single writer; reads use the
/// pool's reader connections (04 I2).
public actor GRDBRepository: Repository {
  public let database: AppDatabase

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: - Accounts

  public func insertAccount(_ account: AccountRecord) async throws {
    try await database.write("insertAccount") { db in
      try Self.translatingConstraints(account.id) {
        try account.insert(db)
        for job in Job.allCases {
          try db.execute(
            sql: "INSERT INTO poll_state (account_id, job) VALUES (?, ?)", arguments: [account.id, job.rawValue]
          )
        }
      }
    }
  }

  public func updateAccount(_ account: AccountRecord) async throws {
    try await database.write("updateAccount") { db in
      try Self.translatingConstraints(account.id) {
        do {
          try account.update(db)
        } catch RecordError.recordNotFound {
          throw StoreError.notFound(account.id)
        }
      }
    }
  }

  public func deleteAccount(id: String) async throws {
    let deleted = try await database.write("deleteAccount") { db in
      try AccountRecord.deleteOne(db, key: id)
    }
    guard deleted else { throw StoreError.notFound(id) }
  }

  public func fetchAccounts() async throws -> [AccountRecord] {
    try await database.read { db in
      try AccountRecord.order(Column("created_at"), Column("id")).fetchAll(db)
    }
  }

  // MARK: - Maintenance

  public func backup() async throws -> BackupResult {
    try await database.backup()
  }

  public func integrityCheck() async throws -> IntegrityResult {
    try await database.integrityCheck()
  }

  public func quickCheck() async throws -> IntegrityResult {
    try await database.quickCheck()
  }

  public func incrementalVacuum() async throws -> Int {
    try await database.incrementalVacuum()
  }

  /// A primary-key or UNIQUE violation becomes `StoreError.duplicate`; other errors pass through.
  static func translatingConstraints<T>(_ key: String, _ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch let error as DatabaseError
              where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE
              || error.extendedResultCode == .SQLITE_CONSTRAINT_PRIMARYKEY {
      throw StoreError.duplicate("\(key): \(error.message ?? "constraint")")
    }
  }
}
