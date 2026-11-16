import Foundation

/// 06 § Tailing 1 and 3–4 and § processLine: scanning the folder and reading each file (14 § Stage 7.2 step 3).
extension IngestService {
  // MARK: - Scanning

  /// Reads every accepted file that changed. A scan requested during a scan runs once more after it, so one file is
  /// never read by two scans at once.
  public func scan() async {
    guard !scanning else {
      rescanRequested = true
      return
    }
    scanning = true
    repeat {
      rescanRequested = false
      await scanOnce()
    } while rescanRequested
    scanning = false
  }

  func scanOnce() async {
    let entries: [URL]
    do {
      entries = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
      ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    } catch {
      log.emit(.error, .ingestReadFailed, cat: .ingest, msg: "ingest folder not listed", err: error, ctx: [
        "file": .string(folder.lastPathComponent), "attempt": 1
      ])
      return
    }
    var present = 0
    for url in entries where url.lastPathComponent != "ingested" && url.lastPathComponent != "rejected" {
      if let reason = skipReason(url) {
        if skipped.insert(url.path).inserted {
          log.emit(.info, .ingestSkipped, cat: .ingest, msg: "not a harness file", ctx: [
            "path": .string(url.path), "reason": .string(reason)
          ])
        }
        continue
      }
      if await process(url) { present += 1 }
    }
    update { $0.files = present }
  }

  /// 06: `*.jsonl` and `*.ndjson` directly in the folder; hidden files, symlinks and directories are not read.
  func skipReason(_ url: URL) -> String? {
    if url.lastPathComponent.hasPrefix(".") { return "hidden" }
    do {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      if values.isSymbolicLink == true { return "symlink" }
      if values.isDirectory == true { return "dir" }
    } catch {
      // Gone between listing and reading: nothing to skip or read.
      return "gone"
    }
    return ["jsonl", "ndjson"].contains(url.pathExtension.lowercased()) ? nil : "ext"
  }

  /// Reads the file from its offset (06 § Tailing 1 and 3–6). Returns false once it has been moved out.
  func process(_ url: URL) async -> Bool {
    let path = url.path
    let stat: FileStat
    do {
      stat = try FileStat.of(url)
    } catch {
      return await readFailed(url, error)
    }
    var record = files[path]
    var reset = record == nil
    if let known = record, known.inode != stat.inode {
      if known.state == "active" {
        log.emit(.warn, .ingestInodeChanged, cat: .ingest, msg: "file replaced; reading from the start", ctx: [
          "file": .string(url.lastPathComponent), "old": .int(Int(known.inode)), "new": .int(Int(stat.inode))
        ])
      }
      record = nil
      reset = true
    } else if let known = record, known.lastSize > stat.size {
      log.emit(.warn, .ingestTruncated, cat: .ingest, msg: "file truncated; reading from the start", ctx: [
        "file": .string(url.lastPathComponent), "old": .int(Int(known.lastSize)), "new": .int(Int(stat.size))
      ])
      record = nil
      reset = true
    } else if let known = record, known.state != "active" {
      return true
    }
    let offset = record?.offset ?? 0
    if !reset, offset == stat.size {
      scheduleQuiet(url, stat)
      return true
    }
    if stat.size > Self.largeFileBytes, !status.largeFiles.contains(url.lastPathComponent) {
      log.emit(.warn, .ingestLargeFile, cat: .ingest, msg: "large harness file; rotate it", ctx: [
        "file": .string(url.lastPathComponent), "bytes": .int(Int(stat.size))
      ])
      update { $0.largeFiles.append(url.lastPathComponent) }
    }
    return await read(url, stat: stat, from: offset, record: record, reset: reset)
  }

  /// The read loop: complete lines from `offset`, committed every 1 000 lines and at the end.
  func read(_ url: URL, stat: FileStat, from offset: Int64, record: IngestFileRecord?, reset: Bool) async -> Bool {
    var reader = BatchReader(file: url, stat: stat, offset: offset, reset: reset,
                             lineNo: reset ? 0 : (record.map { $0.linesOk + $0.linesBad + $0.linesDup } ?? 0))
    let current = await pricer()
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: url)
      try handle.seek(toOffset: UInt64(offset))
    } catch {
      return await readFailed(url, error)
    }
    defer {
      do {
        try handle.close()
      } catch {
        log.emit(.error, .ingestReadFailed, cat: .ingest, msg: "file not closed", err: error, ctx: [
          "file": .string(url.lastPathComponent), "attempt": 1
        ])
      }
    }
    switch await consume(handle, into: &reader, pricer: current) {
    case .failed(let error): return await readFailed(url, error)
    case .rejectFile(let head): return await rejectFile(url, head: head, stat: stat)
    case .stopped: return true
    case .done: break
    }
    guard await commit(&reader, final: true) else { return true }
    readAttempts[url.path] = nil
    if reader.linesRead > Self.burstLines {
      log.emit(.info, .ingestBurst, cat: .ingest, msg: "burst of lines", ctx: [
        "file": .string(url.lastPathComponent), "lines": .int(reader.linesRead)
      ])
    }
    if reader.end == stat.size { scheduleQuiet(url, stat) }
    return true
  }

  enum Accepted {
    case kept
    case rejectFile(Data)
  }

  enum Consumed {
    case done
    /// A commit failed (already logged); the next change reads the same lines again.
    case stopped
    case rejectFile(Data)
    case failed(any Error)
  }

  /// Every chunk to EOF through the tailer, committing every 1 000 lines.
  func consume(_ handle: FileHandle, into reader: inout BatchReader, pricer: Pricer) async -> Consumed {
    var tailer = Tailer(offset: reader.start)
    do {
      while let chunk = try handle.read(upToCount: Tailer.chunkBytes), !chunk.isEmpty {
        for piece in tailer.feed(chunk) {
          if case .rejectFile(let head) = accept(piece, into: &reader, pricer: pricer) { return .rejectFile(head) }
          if reader.pending.count + Int(reader.rejected) >= Self.batchLines {
            guard await commit(&reader) else { return .stopped }
          }
        }
      }
    } catch {
      return .failed(error)
    }
    return .done
  }

  /// One complete line: parsed, normalized, priced and queued, or counted as rejected and logged.
  func accept(_ piece: Tailer.Piece, into reader: inout BatchReader, pricer: Pricer) -> Accepted {
    reader.lineNo += 1
    reader.linesRead += 1
    let first = reader.end == 0 && reader.lineNo == 1
    let name = reader.file.lastPathComponent
    defer { reader.end = piece.endOffset }
    switch piece.item {
    case .tooLong:
      reader.rejected += 1
      log.emit(.warn, .ingestLineTooLong, cat: .ingest, msg: "line over 64 KiB rejected", ctx: [
        "file": .string(name), "line_no": .int(Int(reader.lineNo))
      ])
    case .line(let data):
      switch LineParser.parse(data) {
      case .failure(let rejection):
        if first && rejection.rejectsFile { return .rejectFile(data) }
        reader.rejected += 1
        var ctx: [String: LogValue] = ["file": .string(name), "line_no": .int(Int(reader.lineNo))]
        if case .badField(let field) = rejection { ctx["field"] = .string(field) }
        log.emit(.warn, rejection.event, cat: .ingest, msg: "harness line rejected", ctx: ctx)
      case .success(let line):
        reader.pending.append(prepare(line, lineNo: reader.lineNo, file: name, pricer: pricer))
      }
    }
    return .kept
  }

  /// The line's cost, its clock flags and its once-per-file / once-per-day diagnostics (06, 05, 07).
  func prepare(_ line: HarnessLine, lineNo: Int64, file: String, pricer: Pricer) -> IngestLine {
    let time = now()
    let futureTs = line.date.timeIntervalSince(time) > Self.futureSkew
    let tooOld = line.date < time.addingTimeInterval(-86_400 * Double(settings.hourlyRetentionDays))
    let lineCtx: [String: LogValue] = ["file": .string(file), "line_no": .int(Int(lineNo)),
                                       "ts": .string(DBTime.string(line.date))]
    if futureTs { log.emit(.warn, .ingestFutureTs, cat: .ingest, msg: "line from the future", ctx: lineCtx) }
    if tooOld { log.emit(.warn, .ingestTooOld, cat: .ingest, msg: "line older than the hourly horizon", ctx: lineCtx) }
    for field in line.unknownFields where notes.insert("\(file)/field/\(field)").inserted {
      log.emit(.info, .ingestUnknownFields, cat: .ingest, msg: "unknown field in harness lines", ctx: [
        "file": .string(file), "fields": .string(field)
      ])
    }
    if line.keyHintTruncated, notes.insert("\(file)/key_hint").inserted {
      log.emit(.info, .ingestKeyHintTruncated, cat: .ingest, msg: "key_hint cut to its last 4 characters", ctx: [
        "file": .string(file), "field": "key_hint"
      ])
    }
    let normal = line.normalization
    let provider = line.provider.rawValue
    if let missing = normal.missingKey {
      log.emit(.error, .normalizeFailed, cat: .normalize, msg: "harness usage not normalized", ctx: [
        "provider": .string(provider), "missing_key": .string(missing), "request_id": .string(line.requestID)
      ])
    }
    for field in normal.negative {
      log.emit(.warn, .normalizeNegative, cat: .normalize, msg: "negative difference clamped to 0", ctx: [
        "provider": .string(provider), "field": .string(field)
      ])
    }
    if !normal.unknownKeys.isEmpty, unknownKeysOnce.first("harness/\(provider)", on: time) {
      log.emit(.info, .normalizeUnknownKeys, cat: .normalize, msg: "unknown usage keys", ctx: [
        "provider": .string(provider), "keys": .string(normal.unknownKeys.joined(separator: ","))
      ])
    }
    var cents = line.classes.flatMap {
      CostEstimator.estimate($0, entry: pricer.lookup(provider: line.provider, model: line.model)?.entry).cents
    }
    if let given = line.costCents { cents = given }
    return IngestLine(line: line, lineNo: lineNo, estCents: cents, futureTs: futureTs, tooOld: tooOld)
  }

  /// Applies the queued lines with the file's position (V7). False when the write failed: nothing moved, and the
  /// next change reads the same lines again (dedup makes that safe).
  func commit(_ reader: inout BatchReader, final: Bool = false) async -> Bool {
    guard !reader.pending.isEmpty || reader.rejected > 0 || (final && (reader.reset || reader.end != reader.start))
    else { return true }
    let pricer = await pricer()
    let file = IngestFileRecord(path: reader.file.path, inode: reader.stat.inode, offset: reader.end,
                                lastSize: reader.stat.size, lastMtime: DBTime.string(reader.stat.mtime),
                                state: "active", linesOk: 0, linesBad: 0, linesDup: 0)
    let batch = IngestBatch(file: file, lines: reader.pending, rejected: reader.rejected,
                            resetCounters: reader.reset, ingestedAt: DBTime.string(now())) { row, provider in
      pricer.price(row, provider: provider).0
    }
    let result: IngestBatchResult
    do {
      result = try await store.applyIngestBatch(batch)
    } catch {
      return await readFailed(reader.file, error)
    }
    var stored = files[file.path].flatMap { reader.reset ? nil : $0 } ?? file
    stored.inode = file.inode
    stored.offset = file.offset
    stored.lastSize = file.lastSize
    stored.lastMtime = file.lastMtime
    stored.state = "active"
    stored.linesOk += Int64(result.inserted)
    stored.linesBad += reader.rejected
    stored.linesDup += Int64(result.duplicates.count + result.conflicts.count)
    files[file.path] = stored
    report(result, file: reader.file.lastPathComponent, rejected: Int(reader.rejected),
           lines: reader.pending.count)
    reader.pending = []
    reader.rejected = 0
    reader.reset = false
    reader.start = reader.end
    return true
  }

  func report(_ result: IngestBatchResult, file: String, rejected: Int, lines: Int) {
    for id in result.duplicates {
      log.emit(.debug, .ingestDuplicate, cat: .ingest, msg: "duplicate request", ctx: ["request_id": .string(id)])
    }
    for id in result.conflicts {
      log.emit(.warn, .ingestDuplicateConflict, cat: .ingest, msg: "same request id, different usage; first kept",
               ctx: ["request_id": .string(id)])
    }
    for app in result.appsCreated {
      log.emit(.info, .ingestAppCreated, cat: .ingest, msg: "app created from a harness tag", ctx: [
        "app": .string(app.app), "provider": .string(app.provider)
      ])
    }
    for line in result.ambiguousHints {
      log.emit(.info, .ingestKeyHintAmbiguous, cat: .ingest, msg: "key hint matches several keys", ctx: [
        "file": .string(file), "field": "key_hint", "line_no": .int(Int(line))
      ])
    }
    tally(inserted: result.inserted, duplicate: result.duplicates.count + result.conflicts.count, rejected: rejected,
          read: lines + rejected > 0)
  }

  /// Today's counters (local day): they restart when the day changes.
  func tally(inserted: Int = 0, duplicate: Int = 0, rejected: Int = 0, read: Bool = false) {
    let day = Self.localDay(now())
    let time = now()
    update { status in
      if status.day != day {
        status.day = day
        status.linesOK = 0
        status.linesDuplicate = 0
        status.linesRejected = 0
      }
      status.linesOK += inserted
      status.linesDuplicate += duplicate
      status.linesRejected += rejected
      if read { status.lastLineAt = time }
    }
  }
}
