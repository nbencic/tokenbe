import Foundation
import Security
import Testing
@testable import TokenBeCore

extension Tag {
  /// Touches the real login keychain, under the test service only (11 § KeyStoreTests).
  @Tag static var keychainIntegration: Self
}

/// 14 § Stage 3.2 Tests: `KeyStore` semantics on `InMemoryKeyStore`; `KeychainKeyStore`'s status mapping and its
/// 07 events, which never carry the secret.
@Suite struct KeyStoreTests {
  @Test("get, set, overwrite, delete; deleting a missing item succeeds")
  func semantics() async throws {
    let store = InMemoryKeyStore()
    #expect(try await store.get("openai") == nil)
    try await store.set("openai", secret: "first secret")
    #expect(try await store.get("openai") == "first secret")
    try await store.set("openai", secret: "second secret")
    #expect(try await store.get("openai") == "second secret")
    try await store.delete("openai")
    #expect(try await store.get("openai") == nil)
    try await store.delete("openai")
    #expect(await store.refs.isEmpty)
  }

  @Test("an injected failure is thrown by that operation only")
  func injectedFailure() async throws {
    let store = InMemoryKeyStore(["xai": "kept"])
    await store.fail(.write, with: .failed(op: .write, status: errSecDuplicateItem))
    await #expect(throws: KeyStoreError.failed(op: .write, status: errSecDuplicateItem)) {
      try await store.set("xai", secret: "new")
    }
    #expect(try await store.get("xai") == "kept")
  }

  @Test("OSStatus classification")
  func classify() {
    #expect(KeychainKeyStore.classify(errSecSuccess, .read) == nil)
    #expect(KeychainKeyStore.classify(errSecInteractionNotAllowed, .read)
            == .accessDenied(op: .read, status: errSecInteractionNotAllowed))
    #expect(KeychainKeyStore.classify(errSecAuthFailed, .write) == .accessDenied(op: .write, status: errSecAuthFailed))
    #expect(KeychainKeyStore.classify(errSecDuplicateItem, .write) == .failed(op: .write, status: errSecDuplicateItem))
    #expect(KeychainKeyStore.classify(errSecUserCanceled, .delete) == .failed(op: .delete, status: errSecUserCanceled))
  }

  @Test("each failure logs its 07 event with acct and osstatus, at error or fault")
  func events() async {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    let store = KeychainKeyStore(service: "dev.bathyon.tokenbe.test", logPipeline: pipeline)
    struct Case {
      let error: KeyStoreError
      let evt: Evt
      let lvl: LogLevel
    }
    let cases = [
      Case(error: .failed(op: .read, status: -1), evt: .keychainReadFailed, lvl: .error),
      Case(error: .failed(op: .write, status: -2), evt: .keychainWriteFailed, lvl: .error),
      Case(error: .failed(op: .delete, status: -3), evt: .keychainDeleteFailed, lvl: .error),
      Case(error: .accessDenied(op: .read, status: errSecInteractionNotAllowed), evt: .keychainAccessDenied, lvl: .fault)
    ]
    for item in cases { #expect(store.report(item.error, "openai") == item.error) }
    await pipeline.drain()
    let records = await sink.records
    #expect(records.map(\.evt) == cases.map(\.evt))
    #expect(records.map(\.lvl) == cases.map(\.lvl))
    #expect(records.allSatisfy { $0.cat == .keychain && $0.acct == "openai" })
    #expect(records.map { $0.ctx["osstatus"] } == [.int(-1), .int(-2), .int(-3), .int(Int(errSecInteractionNotAllowed))])
  }
}

/// `KeychainKeyStore` on the real login keychain, service `dev.bathyon.tokenbe.test` only: never the owner's items
/// (11 § KeyStoreTests, SEC-2 as far as the login keychain reports it, Q-027). Skipped when the keychain cannot be
/// used without interaction (locked, or a headless session).
@Suite(.tags(.keychainIntegration), .enabled(if: KeychainProbe.usable, "login keychain locked or unavailable"))
struct KeychainKeyStoreIntegrationTests {
  static let service = "dev.bathyon.tokenbe.test"

  @Test("write, read, overwrite, delete; item attributes; no synchronizable copy")
  func roundTrip() async throws {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    let store = KeychainKeyStore(service: Self.service, logPipeline: pipeline)
    let ref = "itest-\(UUID().uuidString)"
    defer { SecItemDelete(store.query(ref) as CFDictionary) }

    #expect(try await store.get(ref) == nil)
    #expect(try await !store.contains(ref))
    try await store.set(ref, secret: "integration secret one")
    #expect(try await store.get(ref) == "integration secret one")
    #expect(try await store.contains(ref), "contains reads attributes only (04 startup step 3)")
    try await store.set(ref, secret: "integration secret two")
    #expect(try await store.get(ref) == "integration secret two")

    let attributes = try #require(Self.attributes(service: Self.service, ref: ref))
    #expect(attributes[kSecClass as String] as? String == kSecClassGenericPassword as String)
    #expect(attributes[kSecAttrService as String] as? String == Self.service)
    #expect(attributes[kSecAttrAccount as String] as? String == ref)
    #expect(Self.count(service: Self.service, ref: ref, synchronizable: true) == 0, "never synchronizable")
    #expect(Self.count(service: Self.service, ref: ref, synchronizable: false) == 1, "exactly one item, overwritten")
    #expect(Self.count(service: KeychainKeyStore.service, ref: ref, synchronizable: false) == 0,
            "nothing under the production service")

    try await store.delete(ref)
    #expect(try await store.get(ref) == nil)
    #expect(try await !store.contains(ref))
    try await store.delete(ref)
    await pipeline.drain()
    #expect(await sink.records.isEmpty, "no failure events on the happy path")
  }

  static func attributes(service: String, ref: String) -> [String: Any]? {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: ref, kSecReturnAttributes as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    guard var attributes = result as? [String: Any] else { return nil }
    attributes[kSecClass as String] = attributes["class"] ?? attributes[kSecClass as String]
    return attributes
  }

  static func count(service: String, ref: String, synchronizable: Bool) -> Int {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: ref, kSecAttrSynchronizable as String: synchronizable,
                                kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return status == errSecSuccess ? (result as? [Any])?.count ?? 0 : 0
  }
}

/// Whether the login keychain accepts a write without user interaction, tried once per test run on the test service.
enum KeychainProbe {
  static let usable: Bool = {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: KeychainKeyStoreIntegrationTests.service,
                                kSecAttrAccount as String: "probe-\(UUID().uuidString)"]
    var item = query
    item[kSecValueData as String] = Data("probe".utf8)
    let added = SecItemAdd(item as CFDictionary, nil)
    SecItemDelete(query as CFDictionary)
    return added == errSecSuccess
  }()
}
