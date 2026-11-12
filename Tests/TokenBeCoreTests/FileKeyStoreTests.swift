import Foundation
import Security
import Testing
@testable import TokenBeCore

/// `FileKeyStore` (DEBUG, `TOKENBE_TEST_ROOT` only; PM-3.2-1, Q-030): the UI tests' key file. Round trip, and the
/// read/write/delete failures with their `keychain.*` events (PM-0.5-2).
@Suite struct FileKeyStoreTests {
  struct Fixture {
    let temp: TempDirectory
    let pipeline: LogPipeline
    let sink: CapturingLogSink
  }

  static func harness() throws -> Fixture {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    return Fixture(temp: try TempDirectory(), pipeline: pipeline, sink: sink)
  }

  /// Built at run time so no key-shaped literal is committed (Q-028).
  static let secret = "sk-" + "admin-" + String(repeating: "Fk3", count: 14)

  @Test("set, get, contains, overwrite, delete; a missing file reads as empty")
  func roundTrip() async throws {
    let fixture = try Self.harness()
    let (temp, pipeline, sink) = (fixture.temp, fixture.pipeline, fixture.sink)
    let store = FileKeyStore(directory: temp.url.appendingPathComponent("root"), logPipeline: pipeline)
    #expect(try await store.get("openai") == nil)
    #expect(try await store.contains("openai") == false)
    try await store.set("openai", secret: Self.secret)
    try await store.set("xai", secret: "other")
    #expect(try await store.get("openai") == Self.secret)
    #expect(try await store.contains("openai"))
    try await store.set("openai", secret: "replaced")
    #expect(try await store.get("openai") == "replaced")
    try await store.delete("openai")
    try await store.delete("openai")
    #expect(try await store.get("openai") == nil)
    #expect(try await store.get("xai") == "other")
    await pipeline.drain()
    #expect(await sink.records.isEmpty)
  }

  @Test("an unreadable file throws a read failure and logs keychain.read_failed")
  func unreadable() async throws {
    let fixture = try Self.harness()
    let (temp, pipeline, sink) = (fixture.temp, fixture.pipeline, fixture.sink)
    try Data("not json".utf8).write(to: temp.url.appendingPathComponent(FileKeyStore.fileName))
    let store = FileKeyStore(directory: temp.url, logPipeline: pipeline)
    await #expect(throws: KeyStoreError.failed(op: .read, status: errSecIO)) { try await store.get("openai") }
    await #expect(throws: KeyStoreError.failed(op: .read, status: errSecIO)) { try await store.set("openai", secret: "x") }
    await pipeline.drain()
    let records = await sink.records
    #expect(records.map(\.evt) == [.keychainReadFailed, .keychainReadFailed])
    #expect(records.allSatisfy { $0.lvl == .error && $0.ctx["osstatus"] == .int(Int(errSecIO)) })
  }

  @Test("a file that cannot be written logs keychain.write_failed or keychain.delete_failed")
  func unwritable() async throws {
    let fixture = try Self.harness()
    let (temp, pipeline, sink) = (fixture.temp, fixture.pipeline, fixture.sink)
    // A readable key file in a read-only folder: reads work, the atomic write (a temp file + rename) fails.
    let folder = temp.url.appendingPathComponent("ro", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: folder.appendingPathComponent(FileKeyStore.fileName))
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
    defer {
      do {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
      } catch {
        Issue.record("permissions not restored: \(error)")
      }
    }
    let store = FileKeyStore(directory: folder, logPipeline: pipeline)
    await #expect(throws: KeyStoreError.failed(op: .write, status: errSecIO)) {
      try await store.set("openai", secret: Self.secret)
    }
    await #expect(throws: KeyStoreError.failed(op: .delete, status: errSecIO)) { try await store.delete("openai") }
    await pipeline.drain()
    #expect(await sink.records.map(\.evt) == [.keychainWriteFailed, .keychainDeleteFailed])
    #expect(await sink.lines().joined().contains(Self.secret) == false, "the secret never reaches a record")
  }
}
