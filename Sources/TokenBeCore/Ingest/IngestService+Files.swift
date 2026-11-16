import Darwin
import Foundation

/// 06 § Tailing 5–6 and the failure table: moving files to `ingested/` and `rejected/`, read failures, file state.
extension IngestService {
  // MARK: - Moving files

  /// 06 § Tailing 6: the whole file to `rejected/`, `state = 'rejected'`, `ingest.file_rejected` with its head.
  func rejectFile(_ url: URL, head: Data, stat: FileStat) async -> Bool {
    guard let moved = move(url, to: rejectedFolder, stamped: false) else { return true }
    let text = String(bytes: head.prefix(200), encoding: .utf8) ?? ""
    log.emit(.warn, .ingestFileRejected, cat: .ingest, msg: "not a v1 harness file", ctx: [
      "file": .string(url.lastPathComponent), "head": .string(log.redactor.redact(text))
    ])
    log.emit(.info, .ingestMoved, cat: .ingest, msg: "file moved", ctx: [
      "file": .string(moved.lastPathComponent), "to": "rejected"
    ])
    await setState(url, stat: stat, state: "rejected", offset: 0, rejected: 1)
    tally(rejected: 1)
    return false
  }

  /// 06 failure table: a read that fails is retried at the next change, up to 5 times; then `state = 'rejected'`.
  func readFailed(_ url: URL, _ error: any Error) async -> Bool {
    let attempt = (readAttempts[url.path] ?? 0) + 1
    readAttempts[url.path] = attempt
    log.emit(.error, .ingestReadFailed, cat: .ingest, msg: "harness file not read", err: error, ctx: [
      "file": .string(url.lastPathComponent), "attempt": .int(attempt)
    ])
    if attempt >= Self.maxReadAttempts, let stat = statOrNil(url) {
      await setState(url, stat: stat, state: "rejected", offset: files[url.path]?.offset ?? 0, rejected: 0)
      readAttempts[url.path] = nil
    }
    return true
  }

  func statOrNil(_ url: URL) -> FileStat? {
    do {
      return try FileStat.of(url)
    } catch {
      // Already logged by the caller's `ingest.read_failed`.
      return nil
    }
  }

  func setState(_ url: URL, stat: FileStat, state: String, offset: Int64, rejected: Int64) async {
    let known = files[url.path]
    let reset = known?.inode != stat.inode
    var file = IngestFileRecord(path: url.path, inode: stat.inode, offset: offset, lastSize: stat.size,
                                lastMtime: DBTime.string(stat.mtime), state: state, linesOk: 0, linesBad: 0,
                                linesDup: 0)
    do {
      _ = try await store.applyIngestBatch(IngestBatch(file: file, rejected: rejected, resetCounters: reset,
                                                       ingestedAt: DBTime.string(now())))
      if let known, !reset {
        file.linesOk = known.linesOk
        file.linesBad = known.linesBad + rejected
        file.linesDup = known.linesDup
      } else {
        file.linesBad = rejected
      }
      files[url.path] = file
    } catch {
      log.emit(.error, .ingestReadFailed, cat: .ingest, msg: "file state not saved", err: error, ctx: [
        "file": .string(url.lastPathComponent), "attempt": 1
      ])
    }
  }

  /// 06 § Tailing 5: quiet for 2 s after reaching EOF → maybe move to `ingested/`.
  func scheduleQuiet(_ url: URL, _ stat: FileStat) {
    quiet[url.path]?.cancel()
    let clock = clock
    let delay = quiescence
    quiet[url.path] = Task { [weak self] in
      do {
        try await clock.sleep(for: delay)
      } catch {
        // Cancelled by a newer read of the same file: that read schedules its own check.
        return
      }
      await self?.quiesce(url, stat)
    }
  }

  func quiesce(_ url: URL, _ seen: FileStat) async {
    quiet[url.path] = nil
    guard settings.enabled, settings.moveWhenDone, let stat = statOrNil(url), stat == seen,
          files[url.path]?.offset == stat.size else { return }
    // 06: nobody else holds the file if an exclusive, non-blocking lock succeeds; otherwise leave it in place.
    let descriptor = open(url.path, O_WRONLY | O_EXLOCK | O_NONBLOCK)
    guard descriptor >= 0 else { return }
    close(descriptor)
    guard let moved = move(url, to: ingestedFolder, stamped: true) else { return }
    log.emit(.info, .ingestMoved, cat: .ingest, msg: "file moved", ctx: [
      "file": .string(moved.lastPathComponent), "to": "ingested"
    ])
    await setState(url, stat: stat, state: "ingested", offset: stat.size, rejected: 0)
    update { $0.files = max(0, $0.files - 1) }
  }

  /// Moves the file, `name.YYYYMMDD-HHMMSS.ext` (UTC) into `ingested/`; `-2`, `-3` on a collision.
  func move(_ url: URL, to directory: URL, stamped: Bool) -> URL? {
    let ext = url.pathExtension
    let stem = url.deletingPathExtension().lastPathComponent + (stamped ? "." + Self.stamp(now()) : "")
    var target = directory.appendingPathComponent(stem).appendingPathExtension(ext)
    var number = 2
    while FileManager.default.fileExists(atPath: target.path) {
      target = directory.appendingPathComponent("\(stem)-\(number)").appendingPathExtension(ext)
      number += 1
    }
    do {
      try FileManager.default.moveItem(at: url, to: target)
      return target
    } catch {
      log.emit(.error, .ingestReadFailed, cat: .ingest, msg: "file not moved", err: error, ctx: [
        "file": .string(url.lastPathComponent), "attempt": 1
      ])
      return nil
    }
  }

  static func stamp(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let part = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(format: "%04d%02d%02d-%02d%02d%02d", part.year ?? 0, part.month ?? 0, part.day ?? 0,
                  part.hour ?? 0, part.minute ?? 0, part.second ?? 0)
  }

  static func localDay(_ date: Date) -> String {
    let part = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", part.year ?? 0, part.month ?? 0, part.day ?? 0)
  }
}

/// The state of one read: where it started and stands, and the lines not yet committed.
struct BatchReader {
  let file: URL
  let stat: FileStat
  /// The offset of the last commit (or of the read's start).
  var start: Int64
  /// The offset after the last complete line seen.
  var end: Int64
  var reset: Bool
  var lineNo: Int64
  var linesRead = 0
  var pending: [IngestLine] = []
  var rejected: Int64 = 0

  init(file: URL, stat: FileStat, offset: Int64, reset: Bool, lineNo: Int64) {
    self.file = file
    self.stat = stat
    start = offset
    end = offset
    self.reset = reset
    self.lineNo = lineNo
  }
}
