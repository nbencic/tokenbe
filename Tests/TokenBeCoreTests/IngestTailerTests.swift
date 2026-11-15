import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 11 `IngestTailerTests` (14 § Stage 7.2): the partial line, the offset in the same transaction as the rows (V7),
/// inode change and truncation, dedup and conflicts, rejected files, counters; plus quiescence, the watchers and the
/// folder rules of 06. Every folder is a temp folder; the clock is a `TestClock`.
@Suite struct IngestTailerTests {
  // MARK: - Tailer

  @Test("complete lines only: the fragment without \\n waits; lines split across chunks; blank lines skipped")
  func tailer() {
    var tailer = Tailer(offset: 10)
    #expect(tailer.feed(Data("ab\n\n  \ncd".utf8)) == [.init(item: .line(Data("ab".utf8)), endOffset: 13)])
    #expect(tailer.feed(Data("e\nf".utf8)) == [.init(item: .line(Data("cde".utf8)), endOffset: 21)])
    let long = Data(repeating: 0x61, count: LineParser.maxLineBytes)
    #expect(tailer.feed(long).isEmpty, "the over-long line is counted, not kept")
    #expect(tailer.feed(Data("g\nok\n".utf8)) == [
      .init(item: .tooLong(bytes: LineParser.maxLineBytes + 2), endOffset: 21 + Int64(LineParser.maxLineBytes) + 3),
      .init(item: .line(Data("ok".utf8)), endOffset: 21 + Int64(LineParser.maxLineBytes) + 6)
    ])
  }

  // MARK: - Reading

  @Test("valid_500: 488 events, 12 duplicates, 3 apps, offsets at EOF; DeepSeek lines bucketed, xAI's kept (O-12)")
  func valid500() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try harness.drop("valid_500.jsonl")
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 488)
    let file = try #require(try await harness.file("valid_500.jsonl"))
    let size = try FileStat.of(harness.folder.appendingPathComponent("valid_500.jsonl")).size
    #expect(file.offset == size && file.lastSize == size && file.state == "active")
    #expect(file.linesOk == 488 && file.linesDup == 12 && file.linesBad == 0)
    #expect(try await harness.count("SELECT count(*) FROM app WHERE is_auto = 1 AND name != 'unassigned'") == 3)
    #expect(try await harness.count("""
      SELECT count(*) FROM app_binding WHERE kind = 'harness_tag' AND account_id = 'acct-deepseek'
      """) == 3)
    #expect(try await harness.count("SELECT count(*) FROM harness_event WHERE account_id IS NULL") == 97,
            "xAI has no account: stored, counted, no bucket")
    #expect(try await harness.count("SELECT count(*) FROM harness_event WHERE provider_key_id = 'dskey-1'") == 391)
    #expect(try await harness.count("""
      SELECT sum(requests) FROM usage_bucket WHERE source = 'harness' AND provider_key_id = 'dskey-1'
      """) == 391)
    #expect(try await harness.count("SELECT count(*) FROM usage_bucket WHERE source = 'harness' AND unpriced = 1") == 0,
            "deepseek-chat is priced, so the buckets are")
    #expect(try await harness.count("SELECT count(*) FROM harness_event WHERE est_cost_cents IS NULL") == 0,
            "deepseek-chat and grok-4 are both in the test price feed")
    #expect(await harness.records(.ingestAppCreated).count == 3)
    #expect(await harness.records(.ingestStart).first?.ctx["mode"] == "fsevents")
    let status = await harness.service.status
    #expect(status.linesOK == 488 && status.linesDuplicate == 12 && status.files == 1 && status.lastLineAt != nil)
  }

  @Test("a partial last line is not consumed; it is read once its \\n arrives")
  func partialLine() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try harness.drop("partial_write.jsonl")
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 3)
    let url = harness.folder.appendingPathComponent("partial_write.jsonl")
    let text = try String(contentsOf: url, encoding: .utf8)
    let fragment = String(text[text.index(after: try #require(text.lastIndex(of: "\n")))...])
    #expect(try await harness.file("partial_write.jsonl")?.offset == Int64(text.utf8.count - fragment.utf8.count))
    // The fixture's 4th line, cut after 40 bytes (Tests/Fixtures/harness); the harness finishes writing it.
    let fourth = "{\"v\":1,\"ts\":\"2026-11-10T00:06:00.000Z\",\"provider\":\"deepseek\",\"app\":\"weather-collector\"," +
      "\"key_hint\":\"a9f2\",\"request_id\":\"req-deepseek-0003\",\"model\":\"deepseek-chat\",\"usage\":" +
      "{\"prompt_tokens\":1003,\"completion_tokens\":200,\"prompt_cache_hit_tokens\":600,\"prompt_cache_miss_tokens\":403}," +
      "\"status\":\"ok\"}"
    #expect(fourth.hasPrefix(fragment))
    try harness.append(String(fourth.dropFirst(fragment.count)) + "\n", to: "partial_write.jsonl")
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 4)
    #expect(try await harness.file("partial_write.jsonl")?.linesBad == 0)
  }

  @Test("V7: a failing ingest_file write rolls back the batch's events and buckets; the next read retries")
  func rollback() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try await harness.database.write("trigger") { db in
      try db.execute(sql: """
        CREATE TRIGGER fail_ingest_file BEFORE INSERT ON ingest_file BEGIN SELECT RAISE(ABORT, 'injected'); END
        """)
    }
    try harness.write(IngestHarness.line("r1") + IngestHarness.line("r2"), to: "a.jsonl")
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 0)
    #expect(try await harness.count("SELECT count(*) FROM usage_bucket") == 0)
    #expect(try await harness.count("SELECT count(*) FROM app WHERE name != 'unassigned'") == 0)
    #expect(await harness.records(.ingestReadFailed).first?.ctx["file"] == "a.jsonl")
    try await harness.database.write("untrigger") { db in try db.execute(sql: "DROP TRIGGER fail_ingest_file") }
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 2)
    #expect(try await harness.file("a.jsonl")?.linesOk == 2)
  }

  @Test("an inode change or a truncation reads the file again from offset 0 and restarts its counters")
  func inodeAndTruncation() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try harness.write(IngestHarness.line("r1") + IngestHarness.line("r2"), to: "a.jsonl")
    await harness.service.scan()
    // Replaced: a new file under the same name.
    try FileManager.default.removeItem(at: harness.folder.appendingPathComponent("a.jsonl"))
    try harness.write(IngestHarness.line("r3"), to: "a.jsonl")
    await harness.service.scan()
    #expect(await harness.records(.ingestInodeChanged).count == 1)
    #expect(try await harness.file("a.jsonl")?.linesOk == 1)
    // Truncated in place: shorter than last time.
    try harness.append(IngestHarness.line("r4") + IngestHarness.line("r5"), to: "a.jsonl")
    await harness.service.scan()
    let handle = try FileHandle(forWritingTo: harness.folder.appendingPathComponent("a.jsonl"))
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data(IngestHarness.line("r6").utf8))
    try handle.close()
    await harness.service.scan()
    #expect(await harness.records(.ingestTruncated).count == 1)
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 6)
    #expect(try await harness.file("a.jsonl")?.linesOk == 1)
  }

  @Test("dedup: the same request again is a duplicate; with different usage, a conflict, and the first wins")
  func dedupAndConflict() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try harness.write(IngestHarness.line("r1"), to: "a.jsonl")
    try harness.write(IngestHarness.line("r1") + IngestHarness.line("r1", prompt: 5), to: "b.jsonl")
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 1)
    #expect(try await harness.count("SELECT sum(requests) FROM usage_bucket") == 1, "a duplicate changes no bucket")
    #expect(try await harness.file("b.jsonl")?.linesDup == 2)
    let conflict = try #require(await harness.records(.ingestDuplicateConflict).first)
    #expect(conflict.lvl == .warn && conflict.ctx["request_id"] == "r1")
    #expect(try await harness.count("""
      SELECT count(*) FROM harness_event WHERE json_extract(usage_json, '$.prompt_tokens') = 1000
      """) == 1)
  }

  @Test("a file whose first line is not v1 JSON goes to rejected/ whole; bad later lines are counted")
  func rejectedFiles() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    for name in ["bad_json.jsonl", "bad_version.jsonl", "unknown_provider.jsonl", "too_long_line.jsonl"] {
      try harness.drop(name)
    }
    await harness.service.scan()
    let rejected = try FileManager.default.contentsOfDirectory(atPath: harness.folder.appendingPathComponent("rejected").path)
    #expect(Set(rejected) == ["bad_json.jsonl", "bad_version.jsonl"])
    #expect(try await harness.file("bad_json.jsonl")?.state == "rejected")
    let record = try #require(await harness.records(.ingestFileRejected).first { $0.ctx["file"] == "bad_json.jsonl" })
    #expect(record.ctx["head"] == .string("{\"v\":1,\"ts\":\"2026-11-10T00:00:00Z\", not json"))
    #expect(await harness.records(.ingestMoved).filter { $0.ctx["to"] == "rejected" }.count == 2)
    #expect(try await harness.file("unknown_provider.jsonl")?.linesBad == 1)
    #expect(try await harness.file("unknown_provider.jsonl")?.linesDup == 1,
            "its first line repeats too_long_line.jsonl's, read before it")
    #expect(try await harness.file("too_long_line.jsonl")?.linesBad == 1)
    #expect(try await harness.file("too_long_line.jsonl")?.linesOk == 2)
    #expect(await harness.records(.ingestUnknownProvider).first?.ctx["line_no"] == 2)
    #expect(await harness.records(.ingestLineTooLong).first?.ctx["line_no"] == 2)
    #expect(await harness.service.status.linesRejected == 4)
  }

  @Test("clock skew and age: future lines are flagged, lines past the hourly horizon get no bucket")
  func futureAndOld() async throws {
    let harness = try await IngestHarness(settings: IngestSettings(hourlyRetentionDays: 30))
    await harness.service.start(expectFolder: false)
    try harness.drop("future_ts.jsonl")
    try harness.write(IngestHarness.line("old", ts: "2026-09-01T00:00:00Z"), to: "old.jsonl")
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event WHERE future_ts = 1") == 1)
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 2)
    #expect(try await harness.count("SELECT count(*) FROM usage_bucket WHERE bucket_start LIKE '2026-09%'") == 0)
    #expect(await harness.records(.ingestFutureTs).count == 1)
    #expect(await harness.records(.ingestTooOld).count == 1)
  }

  @Test("key hints: an ambiguous hint stores no key; normalization failure stores NULL classes; OpenRouter cost_cents")
  func keysNormalizeAndCost() async throws {
    let harness = try await IngestHarness()
    try await harness.repository.upsertProviderKeys(accountID: IngestHarness.deepseekAccount, keys: [
      DiscoveredKey(providerKeyID: "dskey-2", name: "other", redacted: "sk-...a9f2")
    ], seenAt: IngestHarness.now)
    await harness.service.start(expectFolder: false)
    let broken = IngestHarness.line("nope").replacingOccurrences(of: "\"prompt_tokens\":1000,", with: "")
    try harness.write(IngestHarness.line("r1") + broken, to: "a.jsonl")
    try harness.drop("openrouter_cost_cents.jsonl")
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event WHERE provider_key_id IS NULL AND provider = 'deepseek'") == 2)
    #expect(await harness.records(.ingestKeyHintAmbiguous).count == 2)
    #expect(try await harness.count("SELECT count(*) FROM harness_event WHERE classes_json IS NULL") == 1)
    #expect(await harness.records(.normalizeFailed).first?.ctx["missing_key"] == "prompt_tokens")
    #expect(try await harness.count("SELECT est_cost_cents FROM harness_event WHERE provider = 'openrouter'") == 7)
  }

  @Test("a burst over 10 000 lines is committed in 1 000-line transactions and logged once")
  func burst() async throws {
    let harness = try await IngestHarness(deepSeekAccount: false)
    await harness.service.start(expectFolder: false)
    try harness.write((0..<10_050).map { IngestHarness.line("b\($0)") }.joined(), to: "big.jsonl")
    await harness.service.scan()
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 10_050)
    #expect(await harness.records(.ingestBurst).first?.ctx["lines"] == 10_050)
  }
}

extension IngestTailerTests {
  // MARK: - Moving, watching, folders

  @Test("quiet for 2 s after EOF: moved to ingested/ with a UTC stamp; not when moveWhenDone is off")
  func quiescence() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try harness.write(IngestHarness.line("r1"), to: "a.jsonl")
    await harness.service.scan()
    await harness.clock.waitForSleepers()
    harness.clock.advance(by: .seconds(2))
    await eventually("moved") {
      !FileManager.default.fileExists(atPath: harness.folder.appendingPathComponent("a.jsonl").path)
    }
    let moved = try FileManager.default.contentsOfDirectory(atPath: harness.folder.appendingPathComponent("ingested").path)
    #expect(moved == ["a.20261110-120000.jsonl"])
    await eventually("state ingested") { await harness.state("a.jsonl") == "ingested" }
    #expect(await harness.records(.ingestMoved).first?.ctx["to"] == "ingested")

    await harness.service.apply(IngestSettings(moveWhenDone: false))
    try harness.write(IngestHarness.line("r2"), to: "b.jsonl")
    await harness.service.scan()
    await harness.clock.waitForSleepers()
    harness.clock.advance(by: .seconds(2))
    try await Task.sleep(for: .milliseconds(100))
    #expect(FileManager.default.fileExists(atPath: harness.folder.appendingPathComponent("b.jsonl").path))
  }

  @Test("hidden files, folders, symlinks and other extensions are skipped and logged once each")
  func skipped() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try harness.write(IngestHarness.line("r1"), to: ".hidden.jsonl")
    try harness.write("x", to: "notes.txt")
    try FileManager.default.createDirectory(at: harness.folder.appendingPathComponent("dir.jsonl"),
                                            withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: harness.folder.appendingPathComponent("link.jsonl"),
                                               withDestinationURL: harness.folder.appendingPathComponent("notes.txt"))
    await harness.service.scan()
    await harness.service.scan()
    let reasons = await harness.records(.ingestSkipped).compactMap { $0.ctx["reason"] }
    #expect(reasons.sorted { "\($0)" < "\($1)" } == ["dir", "ext", "hidden", "symlink"])
    #expect(try await harness.count("SELECT count(*) FROM harness_event") == 0)
  }

  @Test("folders: recreated when missing after the first launch; unwritable disables ingestion")
  func folders() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: true)
    #expect(await harness.records(.ingestFolderRecreated).first?.ctx["path"] == .string(harness.folder.path))
    #expect(FileManager.default.fileExists(atPath: harness.folder.appendingPathComponent("rejected").path))

    let locked = try await IngestHarness()
    try FileManager.default.createDirectory(at: locked.folder, withIntermediateDirectories: true)
    for name in ["ingested", "rejected"] {
      try FileManager.default.createDirectory(at: locked.folder.appendingPathComponent(name),
                                              withIntermediateDirectories: true)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.folder.path)
    defer {
      do {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.folder.path)
      } catch {
        Issue.record("permissions not restored: \(error)")
      }
    }
    await locked.service.start(expectFolder: true)
    #expect(await locked.service.status.mode == .unwritable)
    #expect(await locked.records(.ingestFolderUnwritable).first?.lvl == .error)
    #expect(!locked.watcher.watching)
  }

  @Test("FSEvents unavailable → the 30 s poll; tb.ingest.enabled stops and starts the watch (09)")
  func fallbackAndToggle() async throws {
    let harness = try await IngestHarness(failingWatcher: true)
    await harness.service.start(expectFolder: false)
    #expect(await harness.records(.ingestFseventsFailed).first?.ctx["fallback_poll_s"] == 30)
    #expect(await harness.service.status.mode == .poll && harness.fallback.watching)
    try harness.write(IngestHarness.line("r1"), to: "a.jsonl")
    harness.fallback.fire()
    await eventually("polled") { await harness.events() == 1 }
    await harness.service.apply(IngestSettings(enabled: false))
    #expect(await harness.service.status.mode == .stopped)
    #expect(await harness.records(.ingestStop).first?.ctx["reason"] == "disabled")
    await harness.service.apply(IngestSettings(enabled: true))
    #expect(await harness.records(.ingestStart).count == 2)

    let off = try await IngestHarness(settings: IngestSettings(enabled: false))
    await off.service.start(expectFolder: false)
    #expect(await off.service.status.mode == .stopped && !off.watcher.watching)
  }

  @Test("a file that cannot be read is retried at each change, then rejected after 5 attempts")
  func readFailures() async throws {
    let harness = try await IngestHarness()
    await harness.service.start(expectFolder: false)
    try harness.write(IngestHarness.line("r1"), to: "a.jsonl")
    let path = harness.folder.appendingPathComponent("a.jsonl").path
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
    defer {
      do {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
      } catch {
        Issue.record("permissions not restored: \(error)")
      }
    }
    for _ in 0..<5 { await harness.service.scan() }
    #expect(await harness.records(.ingestReadFailed).map(\.ctx["attempt"]) == [1, 2, 3, 4, 5])
    #expect(try await harness.file("a.jsonl")?.state == "rejected")
    await harness.service.scan()
    #expect(await harness.records(.ingestReadFailed).count == 5, "a rejected file is not read again")
  }

  @Test("PollingWatcher yields every interval of its clock; FSEventsWatcher reports a write in a real folder")
  func watchers() async throws {
    let clock = TestClock()
    let folder = try TempDirectory()
    let polling = PollingWatcher(clock: clock, interval: .seconds(30))
    var ticks = try polling.changes(in: folder.url).makeAsyncIterator()
    await clock.waitForSleepers()
    clock.advance(by: .seconds(30))
    #expect(await ticks.next() == [])

    var events = try FSEventsWatcher(latency: 0.1).changes(in: folder.url).makeAsyncIterator()
    try Data("x\n".utf8).write(to: folder.url.appendingPathComponent("h.jsonl"))
    let paths = await events.next()
    #expect(paths?.contains { $0.hasSuffix("h.jsonl") } == true)
  }
}
