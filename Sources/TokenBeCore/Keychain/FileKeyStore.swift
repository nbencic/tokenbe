#if DEBUG
import Foundation
import Synchronization

/// DEBUG only, and only under `TOKENBE_TEST_ROOT`: keys in a JSON file inside the test root instead of the login
/// keychain (PM-3.2-1, Q-030). UI tests run ad-hoc-signed builds whose code signature changes with every build, so
/// a keychain item one build wrote makes the next build prompt for the login password, and the sandboxed UI-test
/// runner cannot read the app's items at all. The file holds only the fake keys the UI tests type, and lives in the
/// runner's temporary folder. Release builds do not contain this type.
public final class FileKeyStore: KeyStore {
  public static let fileName = "test-keychain.json"

  let url: URL
  private let lock = Mutex(())
  private let log: EventLog

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(directory: URL, logPipeline: LogPipeline? = nil) {
    url = directory.appendingPathComponent(Self.fileName)
    log = EventLog(pipeline: logPipeline)
  }

  public func get(_ ref: String) async throws(KeyStoreError) -> String? {
    try lock.withLock { _ throws(KeyStoreError) in try load()[ref] }
  }

  public func contains(_ ref: String) async throws(KeyStoreError) -> Bool {
    try await get(ref) != nil
  }

  public func set(_ ref: String, secret: String) async throws(KeyStoreError) {
    try lock.withLock { _ throws(KeyStoreError) in
      var items = try load()
      items[ref] = secret
      try save(items, op: .write)
    }
  }

  public func delete(_ ref: String) async throws(KeyStoreError) {
    try lock.withLock { _ throws(KeyStoreError) in
      var items = try load()
      items[ref] = nil
      try save(items, op: .delete)
    }
  }

  private func load() throws(KeyStoreError) -> [String: String] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    do {
      return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    } catch {
      log.emit(.error, .keychainReadFailed, cat: .keychain, msg: "test key file unreadable", err: error,
               ctx: ["osstatus": .int(Int(errSecIO))])
      throw .failed(op: .read, status: errSecIO)
    }
  }

  private func save(_ items: [String: String], op: KeyStoreOp) throws(KeyStoreError) {
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(items).write(to: url, options: .atomic)
    } catch {
      let evt: Evt = op == .delete ? .keychainDeleteFailed : .keychainWriteFailed
      log.emit(.error, evt, cat: .keychain, msg: "test key file not written", err: error,
               ctx: ["osstatus": .int(Int(errSecIO))])
      throw .failed(op: op, status: errSecIO)
    }
  }
}
#endif
