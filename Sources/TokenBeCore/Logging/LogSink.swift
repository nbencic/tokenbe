/// Logging seam (14 § 0.3). Production: `NDJSONSink`, `OSLogSink`. Tests: `CapturingLogSink`.
/// Records arrive already redacted and truncated, in emission order, from one consumer (`LogPipeline`).
public protocol LogSink: Sendable {
  func write(_ record: LogRecord) async
  func flush() async
}
