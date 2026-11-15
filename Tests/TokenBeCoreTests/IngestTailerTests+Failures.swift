import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// The rarer branches of 06's failure table and the service's status stream.
extension IngestTailerTests {
  @Test("status updates stream; overlapping scans run once more; stop before start and a second start are no-ops")
  func statusAndScans() async throws {
    let harness = try await IngestHarness()
    let recorder = StreamRecorder(harness.service.statusUpdates())
    await eventually("the first status") { await recorder.values.count == 1 }
    await harness.service.stop(reason: "quit")
    #expect(await harness.records(.ingestStop).isEmpty, "nothing was started")
    await harness.service.start(expectFolder: false)
    await harness.service.start(expectFolder: false)
    #expect(await harness.records(.ingestStart).count == 1)
    try harness.write(IngestHarness.line("r1"), to: "a.jsonl")
    async let first: Void = harness.service.scan()
    async let second: Void = harness.service.scan()
    _ = await (first, second)
    #expect(await harness.events() == 1)
    await eventually("a status with the line") {
      let last = await recorder.last
      return last?.linesOK == 1 && last?.files == 1
    }
    await recorder.cancel()
  }

  @MainActor
  @Test("IngestSettings mirrors 09's tb.ingest.* and tb.retention.hourlyDays")
  func settingsMirror() {
    let settings = Settings(store: InMemorySettingsStore())
    settings.ingestEnabled = false
    settings.ingestMoveWhenDone = false
    settings.retentionHourlyDays = 45
    #expect(IngestSettings(settings) == IngestSettings(enabled: false, moveWhenDone: false, hourlyRetentionDays: 45))
    #expect(IngestSettings.keys == [.ingestEnabled, .ingestMoveWhenDone, .retentionHourlyDays])
  }

  @Test("unknown fields and a long key hint are logged once per file; unknown usage keys once per day")
  func notes() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    let odd = IngestHarness.line("n1", hint: "sk-0123456789abcdef").replacingOccurrences(of: "\"status\":\"ok\"}",
      with: "\"status\":\"ok\",\"extra\":1}").replacingOccurrences(of: "\"prompt_cache_hit_tokens\":600}",
      with: "\"prompt_cache_hit_tokens\":600,\"novel\":3}")
    try harness.write(odd + odd.replacingOccurrences(of: "n1", with: "n2"), to: "a.jsonl")
    await harness.service.scan()
    #expect(await harness.records(.ingestUnknownFields).map(\.ctx["fields"]) == ["extra"])
    #expect(await harness.records(.ingestKeyHintTruncated).count == 1)
    #expect(await harness.records(.normalizeUnknownKeys).first?.ctx["keys"] == "novel")
    #expect(await harness.records(.normalizeUnknownKeys).count == 1)
  }

  @Test("a file over 512 MiB is read and flagged for rotation (ingest.large_file)")
  func largeFile() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    let url = harness.folder.appendingPathComponent("big.jsonl")
    try harness.write(IngestHarness.line("l1"), to: "big.jsonl")
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(513 * 1024 * 1024))   // sparse: no disk used
    try handle.close()
    await harness.service.scan()
    #expect(await harness.records(.ingestLargeFile).count == 1)
    #expect(await harness.service.status.largeFiles == ["big.jsonl"])
    #expect(await harness.events() == 1, "the zeros after the line are a fragment without \\n")
  }

  @Test("a stamped name already in ingested/ takes -2; a rejected file still in place is not read again")
  func collisionsAndDone() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try Data().write(to: harness.folder.appendingPathComponent("ingested/a.20261110-120000.jsonl"))
    try harness.write(IngestHarness.line("r1"), to: "a.jsonl")
    await harness.service.scan()
    await harness.clock.waitForSleepers()
    harness.clock.advance(by: .seconds(2))
    await eventually("moved with -2") {
      FileManager.default.fileExists(atPath: harness.folder.appendingPathComponent("ingested/a.20261110-120000-2.jsonl").path)
    }
  }

  @Test("FSEvents and the poll both unavailable: ingestion stays off, logged twice")
  func noWatcher() async throws {
    let store = try StoreHarness()
    let database = try await store.open().database
    let folder = store.temp.url.appendingPathComponent("ingest", isDirectory: true)
    let service = IngestService(folder: folder, store: GRDBRepository(database: database),
                                watcher: ManualWatcher(failing: true), fallback: ManualWatcher(failing: true),
                                settings: IngestSettings(), logPipeline: store.pipeline)
    await service.start(expectFolder: false)
    #expect(await store.records(.ingestFseventsFailed).count == 2)
    #expect(await service.status.mode == .stopped)
  }

  @Test("a folder that cannot be created, or that disappears, is reported")
  func brokenFolder() async throws {
    let harness = try await IngestHarness()
    try Data("not a folder".utf8).write(to: harness.folder)
    await harness.service.start(expectFolder: false)
    #expect(await harness.service.status.mode == .unwritable)

    let gone = try await IngestHarness()
    await gone.service.start(expectFolder: false)
    try FileManager.default.removeItem(at: gone.folder)
    await gone.service.scan()
    #expect(await gone.records(.ingestReadFailed).first?.ctx["file"] == "ingest")
  }
}
