import Foundation
import Synchronization

/// Pre-allocated storage for the one `crash.signal` line (07 § Crash handling).
///
/// Writers (the logging pipeline) copy each record, already escaped for a JSON string, into one of 50 fixed slots
/// under `writeLock`. The crash path reads the slots WITHOUT taking a lock — a signal can arrive while a writer holds
/// it — and accepts that the slot being written at that instant may be torn. It only does `memcpy`, integer arithmetic
/// and `write(2)` on memory allocated in `init`, so it never allocates or locks.
///
/// `@unchecked Sendable` invariant (12 § R6): every pointer is allocated once in `init` and never freed or reassigned;
/// slot bytes and lengths are mutated only under `writeLock`, and `appended` is an atomic published after each copy.
/// The only lock-free reader is `writeCrashRecord`, which tolerates torn reads by design. Covered by `CrashHandlerTests`.
public final class CrashRing: @unchecked Sendable {
  public static let slotCount = 50
  public static let slotBytes = 1200
  public static let bufferBytes = 64 * 1024
  static let maxVersionBytes = 100

  /// A pre-rendered byte range. Plain pointer + length: copying it does no reference counting.
  struct Segment {
    let base: UnsafeMutablePointer<UInt8>
    let count: Int

    init(_ text: String) {
      let bytes = Array(text.utf8)
      base = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, bytes.count))
      base.initialize(from: bytes, count: bytes.count)
      count = bytes.count
    }
  }

  private let slots: UnsafeMutablePointer<UInt8>
  private let lengths: UnsafeMutablePointer<Int>
  private let scratch: UnsafeMutablePointer<UInt8>
  private let appended = Atomic<Int>(0)
  private let writeLock = Mutex(())

  private let head: Segment
  private let afterTimestamp: Segment
  private let beforeSignal: Segment
  private let beforePid: Segment
  private let tail: Segment
  private let newline: Segment
  private let nameSIGABRT: Segment
  private let nameSIGBUS: Segment
  private let nameSIGSEGV: Segment
  private let nameSIGILL: Segment
  private let nameSIGTRAP: Segment
  private let nameSIGFPE: Segment
  private let nameException: Segment
  private let nameUnknown: Segment

  public static let exceptionSignal: Int32 = -1

  public init(version: String) {
    slots = UnsafeMutablePointer<UInt8>.allocate(capacity: CrashRing.slotCount * CrashRing.slotBytes)
    slots.initialize(repeating: 0, count: CrashRing.slotCount * CrashRing.slotBytes)
    lengths = UnsafeMutablePointer<Int>.allocate(capacity: CrashRing.slotCount)
    lengths.initialize(repeating: 0, count: CrashRing.slotCount)
    scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: CrashRing.bufferBytes)
    scratch.initialize(repeating: 0, count: CrashRing.bufferBytes)

    let safeVersion = JSONText.escaped(String(version.prefix(CrashRing.maxVersionBytes)))
    head = Segment("{\"ts\":\"")
    afterTimestamp = Segment(
      "\",\"lvl\":\"fault\",\"cat\":\"crash\",\"evt\":\"\(Evt.crashSignal.rawValue)\",\"msg\":\"fatal signal\",\"ctx\":{\"breadcrumbs\":\""
    )
    beforeSignal = Segment("\",\"signal\":\"")
    beforePid = Segment("\"},\"pid\":")
    tail = Segment(",\"thr\":\"crash\",\"v\":\"\(safeVersion)\"}\n")
    newline = Segment("\\n")
    nameSIGABRT = Segment("SIGABRT")
    nameSIGBUS = Segment("SIGBUS")
    nameSIGSEGV = Segment("SIGSEGV")
    nameSIGILL = Segment("SIGILL")
    nameSIGTRAP = Segment("SIGTRAP")
    nameSIGFPE = Segment("SIGFPE")
    nameException = Segment("NSException")
    nameUnknown = Segment("UNKNOWN")
  }

  /// Stores one rendered record line as a breadcrumb (escaped and cut to fit its slot).
  public func record(line: String) {
    let bytes = Array(CrashRing.slotText(line).utf8)
    writeLock.withLock { _ in
      let index = appended.load(ordering: .relaxed) % CrashRing.slotCount
      let slot = slots + index * CrashRing.slotBytes
      bytes.withUnsafeBufferPointer { source in
        if let start = source.baseAddress { slot.update(from: start, count: source.count) }
      }
      lengths[index] = bytes.count
      appended.add(1, ordering: .releasing)
    }
  }

  /// The line escaped for embedding in a JSON string and cut, at a character boundary, to fit one slot.
  static func slotText(_ line: String) -> String {
    let escaped = JSONText.escaped(line)
    if escaped.utf8.count <= slotBytes { return escaped }
    let ellipsis = "…"
    let budget = slotBytes - ellipsis.utf8.count
    var out = ""
    for character in line {
      let piece = JSONText.escaped(String(character))
      if out.utf8.count + piece.utf8.count > budget { break }
      out += piece
    }
    return out + ellipsis
  }

  /// Writes the `crash.signal` line to `fd`. Async-signal-safe: no allocation, no locks, no Swift strings.
  /// Returns the number of bytes handed to `write(2)`, or -1 if `fd` is invalid.
  @discardableResult
  public func writeCrashRecord(signal: Int32, to fd: Int32) -> Int {
    guard fd >= 0 else { return -1 }
    var length = 0
    CrashRing.put(head, into: scratch, at: &length)
    var now = timespec()
    clock_gettime(CLOCK_REALTIME, &now)
    let millis = Int64(now.tv_sec) * 1000 + Int64(now.tv_nsec) / 1_000_000
    length += CrashRing.formatTimestamp(millis: millis, into: scratch + length)
    CrashRing.put(afterTimestamp, into: scratch, at: &length)
    let total = appended.load(ordering: .acquiring)
    let count = min(total, CrashRing.slotCount)
    var index = total - count
    while index < total {
      let slot = index % CrashRing.slotCount
      let slotLength = min(max(lengths[slot], 0), CrashRing.slotBytes)
      if length + slotLength + newline.count <= CrashRing.bufferBytes - 256 {
        (scratch + length).update(from: slots + slot * CrashRing.slotBytes, count: slotLength)
        length += slotLength
        if index + 1 < total { CrashRing.put(newline, into: scratch, at: &length) }
      }
      index += 1
    }
    CrashRing.put(beforeSignal, into: scratch, at: &length)
    CrashRing.put(name(for: signal), into: scratch, at: &length)
    CrashRing.put(beforePid, into: scratch, at: &length)
    length += CrashRing.formatDecimal(Int64(getpid()), into: scratch + length)
    CrashRing.put(tail, into: scratch, at: &length)
    return Darwin.write(fd, scratch, length)
  }

  private func name(for signal: Int32) -> Segment {
    switch signal {
    case SIGABRT: nameSIGABRT
    case SIGBUS: nameSIGBUS
    case SIGSEGV: nameSIGSEGV
    case SIGILL: nameSIGILL
    case SIGTRAP: nameSIGTRAP
    case SIGFPE: nameSIGFPE
    case CrashRing.exceptionSignal: nameException
    default: nameUnknown
    }
  }

  private static func put(_ segment: Segment, into buffer: UnsafeMutablePointer<UInt8>, at length: inout Int) {
    guard length + segment.count <= bufferBytes else { return }
    (buffer + length).update(from: segment.base, count: segment.count)
    length += segment.count
  }

  /// Formats `millis` since 1970 as `YYYY-MM-DDTHH:MM:SS.mmmZ` (24 bytes) using only integer arithmetic.
  static func formatTimestamp(millis: Int64, into out: UnsafeMutablePointer<UInt8>) -> Int {
    let totalSeconds = millis >= 0 ? millis / 1000 : (millis - 999) / 1000
    let milli = millis - totalSeconds * 1000
    var days = totalSeconds >= 0 ? totalSeconds / 86_400 : (totalSeconds - 86_399) / 86_400
    let secondOfDay = totalSeconds - days * 86_400
    // Civil-from-days (H. Hinnant), proleptic Gregorian.
    days += 719_468
    let era = (days >= 0 ? days : days - 146_096) / 146_097
    let dayOfEra = days - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthIndex = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
    let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    var position = 0
    digits(year, width: 4, into: out, at: &position); byte(45, into: out, at: &position)
    digits(month, width: 2, into: out, at: &position); byte(45, into: out, at: &position)
    digits(day, width: 2, into: out, at: &position); byte(84, into: out, at: &position)
    digits(secondOfDay / 3600, width: 2, into: out, at: &position); byte(58, into: out, at: &position)
    digits(secondOfDay % 3600 / 60, width: 2, into: out, at: &position); byte(58, into: out, at: &position)
    digits(secondOfDay % 60, width: 2, into: out, at: &position); byte(46, into: out, at: &position)
    digits(milli, width: 3, into: out, at: &position); byte(90, into: out, at: &position)
    return position
  }

  private static func digits(_ value: Int64, width: Int, into out: UnsafeMutablePointer<UInt8>, at position: inout Int) {
    var remaining = value
    var place = width - 1
    while place >= 0 {
      out[position + place] = UInt8(48 + Int(remaining % 10))
      remaining /= 10
      place -= 1
    }
    position += width
  }

  private static func byte(_ ascii: UInt8, into out: UnsafeMutablePointer<UInt8>, at position: inout Int) {
    out[position] = ascii
    position += 1
  }

  /// Writes a non-negative decimal without allocating.
  static func formatDecimal(_ value: Int64, into out: UnsafeMutablePointer<UInt8>) -> Int {
    var remaining = max(0, value)
    var width = 1
    var probe = remaining
    while probe >= 10 {
      probe /= 10
      width += 1
    }
    var place = width - 1
    while place >= 0 {
      out[place] = UInt8(48 + Int(remaining % 10))
      remaining /= 10
      place -= 1
    }
    return width
  }
}

/// Installs the fatal signal and uncaught-exception handlers that write `crash.signal` (07 § Crash handling).
public enum CrashHandler {
  public static let signals: [Int32] = [SIGABRT, SIGBUS, SIGSEGV, SIGILL, SIGTRAP, SIGFPE]

  /// File descriptor the crash line is appended to; `NDJSONSink` points it at the current log file.
  static let targetFD = Atomic<Int32>(-1)
  static let crashed = Atomic<Bool>(false)

  /// Set once by `install(ring:)`, before any handler can run, and never changed afterwards. Read only on the crash path.
  nonisolated(unsafe) static var installedRing: CrashRing?

  /// Installs the handlers. Call once at launch, after `Log.configure` (startup step 1, 04).
  public static func install(ring: CrashRing) {
    guard installedRing == nil else { return }
    installedRing = ring
    for signalNumber in signals {
      signal(signalNumber, tokenbeFatalSignalHandler)
    }
    NSSetUncaughtExceptionHandler { _ in
      CrashHandler.handleFatal(signal: CrashRing.exceptionSignal)
    }
  }

  /// Points the crash path at `fd` (opened with `O_APPEND`) and closes the previous one.
  public static func setTargetFileDescriptor(_ fd: Int32) {
    let previous = targetFD.exchange(fd, ordering: .acquiringAndReleasing)
    if previous >= 0, previous != fd { close(previous) }
  }

  /// Writes the crash line at most once per process.
  static func handleFatal(signal: Int32) {
    guard let ring = installedRing else { return }
    guard !crashed.exchange(true, ordering: .acquiringAndReleasing) else { return }
    ring.writeCrashRecord(signal: signal, to: targetFD.load(ordering: .acquiring))
  }
}

/// C-convention handler: write the line, restore the default action, re-raise.
private func tokenbeFatalSignalHandler(_ signalNumber: Int32) {
  CrashHandler.handleFatal(signal: signalNumber)
  signal(signalNumber, SIG_DFL)
  raise(signalNumber)
}

/// `~/Library/Application Support/TokenBe/.running`: present while the app runs (07 § Crash handling).
/// If it exists at launch, the previous run did not terminate cleanly and the caller logs `crash.previous_launch`.
public struct RunningSentinel: Sendable {
  public let url: URL

  public init(directory: URL = RunningSentinel.defaultDirectory) {
    url = directory.appendingPathComponent(".running")
  }

  public static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/TokenBe", isDirectory: true)
  }

  public func wasUnclean() -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  /// Creates the sentinel. Call after `wasUnclean()`.
  public func markRunning() throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try Data().write(to: url)
  }

  /// Removes the sentinel on clean terminate.
  public func markClean() throws {
    guard wasUnclean() else { return }
    try FileManager.default.removeItem(at: url)
  }
}
