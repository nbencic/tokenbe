import Foundation
import Security

/// `KeyStore` on the macOS login keychain (04 § Stack, D-keychain-only, Q-027): one `kSecClassGenericPassword` item
/// per account, service `dev.bathyon.tokenbe`, account = `keychain_ref`, written `WhenUnlockedThisDeviceOnly` and
/// never synchronizable. The data-protection keychain is not used: it needs a provisioning-profile entitlement that
/// ad-hoc-signed builds cannot have (Q-027).
///
/// Every `OSStatus` other than success or not-found logs `keychain.read_failed` / `write_failed` /
/// `delete_failed` (error); `errSecInteractionNotAllowed` and `errSecAuthFailed` log `keychain.access_denied`
/// (fault). The secret itself is never logged: records carry only the ref and the status.
public final class KeychainKeyStore: KeyStore {
  public static let service = "dev.bathyon.tokenbe"

  let service: String
  let logPipeline: LogPipeline?

  /// Tests pass `dev.bathyon.tokenbe.test` (11 § KeyStoreTests) and a private log pipeline (PM-2.1-2).
  public init(service: String = KeychainKeyStore.service, logPipeline: LogPipeline? = nil) {
    self.service = service
    self.logPipeline = logPipeline
  }

  func query(_ ref: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
     kSecAttrAccount as String: ref, kSecUseDataProtectionKeychain as String: false]
  }

  public func get(_ ref: String) async throws(KeyStoreError) -> String? {
    var request = query(ref)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    try check(status, .read, ref)
    guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
      throw report(.failed(op: .read, status: errSecDecode), ref)
    }
    return secret
  }

  public func set(_ ref: String, secret: String) async throws(KeyStoreError) {
    let data = Data(secret.utf8)
    let updated = SecItemUpdate(query(ref) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    guard updated == errSecItemNotFound else {
      try check(updated, .write, ref)
      return
    }
    var item = query(ref)
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    item[kSecAttrSynchronizable as String] = false
    try check(SecItemAdd(item as CFDictionary, nil), .write, ref)
  }

  public func delete(_ ref: String) async throws(KeyStoreError) {
    let status = SecItemDelete(query(ref) as CFDictionary)
    if status == errSecItemNotFound { return }
    try check(status, .delete, ref)
  }

  private func check(_ status: OSStatus, _ op: KeyStoreOp, _ ref: String) throws(KeyStoreError) {
    if let error = Self.classify(status, op) { throw report(error, ref) }
  }

  /// Nil for success; `accessDenied` for a locked keychain or a refused authorization; `failed` otherwise.
  static func classify(_ status: OSStatus, _ op: KeyStoreOp) -> KeyStoreError? {
    switch status {
    case errSecSuccess: nil
    case errSecInteractionNotAllowed, errSecAuthFailed: .accessDenied(op: op, status: status)
    default: .failed(op: op, status: status)
    }
  }

  /// Logs the error's 07 event and returns it, so a throw site reads `throw report(…)`.
  func report(_ error: KeyStoreError, _ ref: String) -> KeyStoreError {
    let (op, status): (KeyStoreOp, Int32) = switch error {
    case .accessDenied(let op, let status), .failed(let op, let status): (op, status)
    }
    let evt: Evt = switch error {
    case .accessDenied: .keychainAccessDenied
    case .failed(.read, _): .keychainReadFailed
    case .failed(.write, _): .keychainWriteFailed
    case .failed(.delete, _): .keychainDeleteFailed
    }
    let lvl: LogLevel = if case .accessDenied = error { .fault } else { .error }
    let msg = "keychain \(op.rawValue) failed"
    let ctx: [String: LogValue] = ["osstatus": .int(Int(status))]
    if let logPipeline {
      logPipeline.emit(lvl, evt, cat: .keychain, msg: msg, acct: ref, ctx: ctx)
    } else if lvl == .fault {
      Log.fault(evt, cat: .keychain, msg: msg, acct: ref, ctx: ctx)
    } else {
      Log.error(evt, cat: .keychain, msg: msg, acct: ref, ctx: ctx)
    }
    return error
  }
}
