import Foundation
import GRDB

/// A provider key of one account (03 `provider_key`), as an `app_binding` of kind `provider_key` names it.
public struct ProviderKeyRef: Sendable, Hashable {
  public var accountID: String
  public var providerKeyID: String

  public init(accountID: String, providerKeyID: String) {
    self.accountID = accountID
    self.providerKeyID = providerKeyID
  }
}

/// `app` and `app_binding` rows (03; 14 § Stage 7.1 step 1). The sentinel `unassigned` app (V4) is seeded by the
/// migration and is never created, renamed or bound here.
public protocol AppRepository: Sendable {
  /// Creates an app from a display name: its immutable `name` is the O-16 slug of it (`AppSlug`), unique among every
  /// app. With `binding`, the key is bound to the new app in the same transaction (R7), replacing its old binding.
  func upsertApp(displayName: String, binding: ProviderKeyRef?) async throws -> AppRecord
  /// Changes an app's `display_name` (O-13: `name` never changes). Throws `StoreError.notFound` (also for the
  /// sentinel).
  func upsertApp(id: String, displayName: String) async throws
  /// Every app, the sentinel included, by display name.
  func fetchApps() async throws -> [AppRecord]
  /// Binds a provider key to an app, replacing the key's old binding (03's key is `account_id, kind, value`).
  func bind(appID: String, key: ProviderKeyRef) async throws
  /// Removes the key's binding, if any.
  func unbind(key: ProviderKeyRef) async throws
  /// Every binding, by account, kind and value.
  func fetchBindings() async throws -> [AppBindingRecord]
}

/// O-16: an app's `name` from its display name. Lowercase; every character outside 06's app alphabet
/// (`[a-z0-9._-]`) becomes `-`; repeated `-` collapse to one; the ends are trimmed so the name starts with `[a-z0-9]`
/// (06's regex) and does not end in `-`; at most 64 characters. A collision takes `-2`, `-3`, …, cutting the base so
/// the whole stays within 64 (Q-048). Nothing left (`"!!!"`) is `app`.
public enum AppSlug {
  public static let maxLength = 64
  public static let fallback = "app"

  public static func make(_ displayName: String, taken: Set<String>) -> String {
    let base = base(displayName)
    guard taken.contains(base) else { return base }
    var number = 2
    while true {
      let suffix = "-\(number)"
      let candidate = trim(String(base.prefix(maxLength - suffix.count))) + suffix
      if !taken.contains(candidate) { return candidate }
      number += 1
    }
  }

  static func base(_ displayName: String) -> String {
    var slug = ""
    for scalar in displayName.lowercased().unicodeScalars {
      let allowed = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "." || scalar == "_"
      if allowed {
        slug.unicodeScalars.append(scalar)
      } else if !slug.hasSuffix("-") {
        slug.append("-")
      }
    }
    let trimmed = trim(String(trim(slug).prefix(maxLength)))
    return trimmed.isEmpty ? fallback : trimmed
  }

  /// Drops leading characters until `[a-z0-9]` and trailing `-`.
  static func trim(_ slug: String) -> String {
    let head = slug.drop { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
    return String(head.reversed().drop { $0 == "-" }.reversed())
  }
}

extension GRDBRepository {
  public func upsertApp(displayName: String, binding: ProviderKeyRef?) async throws -> AppRecord {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return try await database.write("upsertApp") { db in
      let taken = Set(try String.fetchAll(db, sql: "SELECT name FROM app"))
      let name = AppSlug.make(trimmed, taken: taken)
      let app = AppRecord(id: UUIDv7.make(), name: name, displayName: trimmed.isEmpty ? name : trimmed,
                          createdAt: DBTime.string(Date()), isAuto: false)
      try app.insert(db)
      if let binding { try Self.bind(db, appID: app.id, key: binding) }
      return app
    }
  }

  public func upsertApp(id: String, displayName: String) async throws {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let changed = try await database.write("renameApp") { db in
      try db.execute(sql: "UPDATE app SET display_name = ? WHERE id = ? AND id != ?",
                     arguments: [trimmed, id, Attribution.unassignedID])
      return db.changesCount
    }
    guard changed == 1 else { throw StoreError.notFound(id) }
  }

  public func fetchApps() async throws -> [AppRecord] {
    try await database.read { db in try AppRecord.order(Column("display_name"), Column("name")).fetchAll(db) }
  }

  public func bind(appID: String, key: ProviderKeyRef) async throws {
    try await database.write("bindApp") { db in try Self.bind(db, appID: appID, key: key) }
  }

  public func unbind(key: ProviderKeyRef) async throws {
    try await database.write("unbindApp") { db in
      try db.execute(sql: """
        DELETE FROM app_binding WHERE account_id = ? AND kind = 'provider_key' AND value = ?
        """, arguments: [key.accountID, key.providerKeyID])
    }
  }

  public func fetchBindings() async throws -> [AppBindingRecord] {
    try await database.read { db in
      try AppBindingRecord.order(Column("account_id"), Column("kind"), Column("value")).fetchAll(db)
    }
  }

  static func bind(_ db: GRDB.Database, appID: String, key: ProviderKeyRef) throws {
    try AppBindingRecord(appId: appID, accountId: key.accountID, kind: "provider_key", value: key.providerKeyID)
      .insert(db, onConflict: .replace)
  }
}
