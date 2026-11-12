import Foundation
import Testing
@testable import TokenBeCore

/// Integrity failures on files that still open (PM-0.5-2), from two fixtures built with the `sqlite3` CLI (GRDB's
/// connections are defensive, so `writable_schema` cannot be used from a test):
/// - `index_mismatch.sqlite`: index `i` is declared on `t(b)` but holds `t(a)`. It passes `quick_check` and fails
///   `integrity_check`, so a running copy is saved and `db.integrity_failed` logged.
/// - `shared_root.sqlite`: the index and its table share one root page. It fails `quick_check` at launch, so the
///   file is moved aside, with `db.integrity_failed` then `db.corrupt`.
@Suite struct IntegrityFailureTests {
  @Test("integrity_check fails on a running database: a copy is saved, db.integrity_failed (fault)")
  func integrityFailsAndCopies() async throws {
    let harness = try StoreHarness()
    try harness.makeDirectory()
    try FixtureDBBuilder.install("index_mismatch.sqlite", into: harness.directory)
    let opened = try await harness.open()
    #expect(opened.recovery == nil, "quick_check does not read index contents")
    let result = try await opened.database.integrityCheck()
    #expect(result.result == "row 1 missing from index i")
    let copy = try #require(result.corruptCopy)
    #expect(FileManager.default.fileExists(atPath: copy.path))
    let failed = try #require(await harness.records(.dbIntegrityFailed).first)
    #expect(failed.lvl == .fault && failed.ctx["check"] == .string("integrity_check"))
    #expect(failed.ctx["corrupt_copy"] == .string(copy.path))
    try opened.database.close()
  }

  @Test("quick_check fails at launch: the file is moved aside, db.integrity_failed then db.corrupt, fresh v1")
  func quickCheckFailsAtLaunch() async throws {
    let harness = try StoreHarness()
    try harness.makeDirectory()
    try FixtureDBBuilder.install("shared_root.sqlite", into: harness.directory)
    let opened = try await harness.open()
    let recovery = try #require(opened.recovery)
    #expect(recovery.restoredFrom == nil)
    #expect(FileManager.default.fileExists(atPath: recovery.corruptCopy.path))
    let failed = try #require(await harness.records(.dbIntegrityFailed).first)
    #expect(failed.ctx["check"] == .string("quick_check"))
    #expect(await harness.records(.dbCorrupt).count == 1)
    #expect(try await opened.database.quickCheck().isOK)
    try opened.database.close()
  }
}
