@testable import TokenBeCore

/// `KeyStore` in memory (14 § 0.3), for every test above the Keychain. A failure can be injected per operation.
actor InMemoryKeyStore: KeyStore {
  private var items: [String: String] = [:]
  private var failures: [KeyStoreOp: KeyStoreError] = [:]

  init(_ items: [String: String] = [:]) {
    self.items = items
  }

  func fail(_ op: KeyStoreOp, with error: KeyStoreError?) {
    failures[op] = error
  }

  var refs: [String] { items.keys.sorted() }

  func get(_ ref: String) async throws(KeyStoreError) -> String? {
    if let failure = failures[.read] { throw failure }
    return items[ref]
  }

  func set(_ ref: String, secret: String) async throws(KeyStoreError) {
    if let failure = failures[.write] { throw failure }
    items[ref] = secret
  }

  func delete(_ ref: String) async throws(KeyStoreError) {
    if let failure = failures[.delete] { throw failure }
    items[ref] = nil
  }
}
