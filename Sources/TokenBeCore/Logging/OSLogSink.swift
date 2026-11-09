import os

/// Mirrors every record to the unified log (07 § Sinks 1): subsystem `dev.bathyon.tokenbe`, one category per `cat`.
/// Lines are redacted before they get here, so they are logged as `.public` and stay readable in Console.app.
public struct OSLogSink: LogSink {
  public static let subsystem = "dev.bathyon.tokenbe"

  public init() {}

  public func write(_ record: LogRecord) async {
    let logger = Logger(subsystem: OSLogSink.subsystem, category: record.cat.name)
    logger.log(level: OSLogSink.osLevel(record.lvl), "\(record.jsonLine(), privacy: .public)")
  }

  /// The unified log persists on its own; nothing is buffered here.
  public func flush() async {}

  static func osLevel(_ level: LogLevel) -> OSLogType {
    switch level {
    case .debug: .debug
    case .info: .info
    case .notice, .warn: .default
    case .error: .error
    case .fault: .fault
    }
  }
}
