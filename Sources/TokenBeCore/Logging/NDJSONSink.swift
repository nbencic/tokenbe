import Foundation

/// The NDJSON file sink (07 § Sinks 2): `~/Library/Logs/TokenBe/tokenbe-YYYY-MM-DD.ndjson`, directory mode `0700`.
///
/// Lines are buffered and written when the buffer reaches 64 KiB, after every `error`/`fault` record, and whenever
/// `flush()` is called (the pipeline calls it every second and on drain/terminate). A new file starts at local
/// midnight or before a line would push the file past 50 MiB (`-N` suffix). Files older than the retention period are
/// deleted, then the oldest files until the total is within 300 MiB; the current file is never deleted.
///
/// Its own failures go to `onFailure` once per failure streak (`app.log_sink_failed`), never back into this sink.
public actor NDJSONSink: LogSink {
  public struct Limits: Sendable {
    public var maxFileBytes: Int
    public var totalCapBytes: Int
    public var flushBytes: Int
    public var retentionDays: Int

    public init(
      maxFileBytes: Int = 50 * 1024 * 1024, totalCapBytes: Int = 300 * 1024 * 1024,
      flushBytes: Int = 64 * 1024, retentionDays: Int = 14
    ) {
      self.maxFileBytes = maxFileBytes
      self.totalCapBytes = totalCapBytes
      self.flushBytes = flushBytes
      self.retentionDays = retentionDays
    }
  }

  public typealias FailureHandler = @Sendable (_ op: String, _ path: String, _ error: any Error) -> Void

  public enum SinkError: Error, Equatable {
    case openFailed(String)
    case openForCrashPathFailed(String)
  }

  public static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TokenBe", isDirectory: true)
  }

  public let directory: URL
  public let limits: Limits
  private let now: @Sendable () -> Date
  private let calendar: Calendar
  private let crashTarget: Bool
  private let onFailure: FailureHandler

  private var buffer = Data()
  private var handle: FileHandle?
  private var currentDay: String?
  private var currentIndex = 0
  private var currentSize = 0
  private var failing = false

  public init(
    directory: URL = NDJSONSink.defaultDirectory,
    limits: Limits = Limits(),
    now: @escaping @Sendable () -> Date = { Date() },
    calendar: Calendar = .current,
    crashTarget: Bool = false,
    onFailure: @escaping FailureHandler = { op, path, error in Log.reportSinkFailure(op: op, path: path, error: error) }
  ) {
    self.directory = directory
    self.limits = limits
    self.now = now
    self.calendar = calendar
    self.crashTarget = crashTarget
    self.onFailure = onFailure
  }

  public func write(_ record: LogRecord) async {
    let line = Data((record.jsonLine() + "\n").utf8)
    let day = dayString(now())
    if day != currentDay {
      flushBuffer()
      openFile(day: day, index: nil)
    } else if currentSize + buffer.count > 0, currentSize + buffer.count + line.count > limits.maxFileBytes {
      flushBuffer()
      openFile(day: day, index: currentIndex + 1)
    }
    buffer.append(line)
    if buffer.count >= limits.flushBytes || record.lvl >= .error {
      flushBuffer()
    }
  }

  public func flush() async {
    flushBuffer()
  }

  /// The file currently written to, if one is open.
  public func currentFileURL() -> URL? {
    currentDay.map { fileURL(day: $0, index: currentIndex) }
  }

  // MARK: - Files

  static func fileName(day: String, index: Int) -> String {
    index == 0 ? "tokenbe-\(day).ndjson" : "tokenbe-\(day)-\(index).ndjson"
  }

  private func fileURL(day: String, index: Int) -> URL {
    directory.appendingPathComponent(NDJSONSink.fileName(day: day, index: index))
  }

  private func dayString(_ date: Date) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// Opens `day`'s file. `index == nil` continues the newest existing file of that day if it has room.
  private func openFile(day: String, index: Int?) {
    closeHandle()
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
      )
    } catch {
      fail("mkdir", directory.path, error)
      return
    }
    var chosen = index ?? 0
    if index == nil {
      let existing = logFiles().filter { $0.day == day }.map(\.index).max() ?? 0
      chosen = existing
      if fileSize(fileURL(day: day, index: existing)) >= limits.maxFileBytes { chosen = existing + 1 }
    }
    let url = fileURL(day: day, index: chosen)
    // O_APPEND: every write lands at the end, so the crash path's own descriptor can never be overwritten.
    let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    guard fd >= 0 else {
      fail(chosen == 0 ? "open" : "rotate", url.path, SinkError.openFailed(String(cString: strerror(errno))))
      return
    }
    do {
      let opened = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
      currentSize = Int(try opened.seekToEnd())
      handle = opened
      currentDay = day
      currentIndex = chosen
    } catch {
      fail(chosen == 0 ? "open" : "rotate", url.path, error)
      return
    }
    if crashTarget { pointCrashPath(at: url) }
    applyRetention()
  }

  private func pointCrashPath(at url: URL) {
    let fd = open(url.path, O_WRONLY | O_APPEND)
    guard fd >= 0 else {
      fail("open", url.path, SinkError.openForCrashPathFailed(String(cString: strerror(errno))))
      return
    }
    CrashHandler.setTargetFileDescriptor(fd)
  }

  private func flushBuffer() {
    guard !buffer.isEmpty else { return }
    guard let handle else {
      // No file could be opened; the records already reached os.Logger and the breadcrumbs.
      buffer.removeAll(keepingCapacity: true)
      return
    }
    do {
      try handle.write(contentsOf: buffer)
      currentSize += buffer.count
      failing = false
    } catch {
      fail("write", currentFileURL()?.path ?? directory.path, error)
    }
    buffer.removeAll(keepingCapacity: true)
  }

  private func closeHandle() {
    guard let handle else { return }
    do {
      try handle.close()
    } catch {
      fail("rotate", currentFileURL()?.path ?? directory.path, error)
    }
    self.handle = nil
  }

  // MARK: - Retention

  struct LogFile {
    let url: URL
    let day: String
    let date: Date
    let index: Int
  }

  private func logFiles() -> [LogFile] {
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    } catch {
      fail("retention", directory.path, error)
      return []
    }
    return names.compactMap { name in
      guard let match = name.wholeMatch(of: /tokenbe-(\d{4})-(\d{2})-(\d{2})(?:-(\d+))?\.ndjson/),
        let year = Int(match.output.1), let month = Int(match.output.2), let day = Int(match.output.3),
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
      else { return nil }
      let index = match.output.4.flatMap { Int($0) } ?? 0
      return LogFile(
        url: directory.appendingPathComponent(name), day: "\(match.output.1)-\(match.output.2)-\(match.output.3)",
        date: date, index: index
      )
    }
  }

  private func fileSize(_ url: URL) -> Int {
    guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      return (attributes[.size] as? NSNumber)?.intValue ?? 0
    } catch {
      fail("retention", url.path, error)
      return 0
    }
  }

  /// Deletes files older than `retentionDays`, then oldest-first until the directory is within `totalCapBytes`.
  private func applyRetention() {
    let current = currentFileURL()?.standardizedFileURL
    let today = calendar.startOfDay(for: now())
    guard let cutoff = calendar.date(byAdding: .day, value: -limits.retentionDays, to: today) else { return }
    var remaining: [LogFile] = []
    for file in logFiles().sorted(by: { ($0.date, $0.index) < ($1.date, $1.index) }) {
      if file.date < cutoff, file.url.standardizedFileURL != current {
        remove(file.url)
      } else {
        remaining.append(file)
      }
    }
    var sizes = remaining.map { fileSize($0.url) }
    var total = sizes.reduce(0, +)
    var position = 0
    while total > limits.totalCapBytes, position < remaining.count {
      if remaining[position].url.standardizedFileURL != current {
        remove(remaining[position].url)
        total -= sizes[position]
        sizes[position] = 0
      }
      position += 1
    }
  }

  private func remove(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      fail("retention", url.path, error)
    }
  }

  private func fail(_ op: String, _ path: String, _ error: any Error) {
    guard !failing else { return }
    failing = true
    onFailure(op, path, error)
  }
}
