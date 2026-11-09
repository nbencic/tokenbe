@testable import TokenBeCore

/// Test sink (14 § 0.3): keeps every record for assertions on `evt` names and redaction.
actor CapturingLogSink: LogSink {
  private(set) var records: [LogRecord] = []
  private(set) var flushCount = 0

  func write(_ record: LogRecord) async { records.append(record) }
  func flush() async { flushCount += 1 }

  func events() -> [Evt] { records.map(\.evt) }
  func lines() -> [String] { records.map { $0.jsonLine() } }
}
