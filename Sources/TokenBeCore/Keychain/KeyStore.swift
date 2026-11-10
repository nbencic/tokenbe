import Foundation

/// Where API keys live (04 § Stack, D-keychain-only, 14 § 0.3). `ref` is `account.keychain_ref` (03): the Keychain
/// account name, never the secret.
///
/// Usage contract (14 § Stage 3.2 step 3, R8): a caller reads the secret only inside the request that needs it,
/// registers it with the `Redactor` for that request and unregisters it in a `defer`; it never stores the secret on
/// a view model, in settings, in the database or in a log.
public protocol KeyStore: Sendable {
  /// Nil when no item exists for `ref`.
  func get(_ ref: String) async throws(KeyStoreError) -> String?
  /// Whether an item exists for `ref`, without reading the secret (04 startup step 3; R8: the secret is read only
  /// inside the request that needs it).
  func contains(_ ref: String) async throws(KeyStoreError) -> Bool
  /// Creates or replaces the item for `ref`.
  func set(_ ref: String, secret: String) async throws(KeyStoreError)
  /// Deleting an item that does not exist succeeds.
  func delete(_ ref: String) async throws(KeyStoreError)
}

/// A Keychain failure, with the `OSStatus` SecItem returned. Each one is logged once where it happens (07).
public enum KeyStoreError: Error, Sendable, Equatable {
  /// `keychain.read_failed` / `write_failed` / `delete_failed` (error).
  case failed(op: KeyStoreOp, status: Int32)
  /// `errSecInteractionNotAllowed` or `errSecAuthFailed`: `keychain.access_denied` (fault).
  case accessDenied(op: KeyStoreOp, status: Int32)
}

public enum KeyStoreOp: String, Sendable, Equatable {
  case read, write, delete
}
