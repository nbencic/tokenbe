import Foundation

/// The file-watching seam (14 § 0.3): `FSEventsWatcher` and its fallback `PollingWatcher` in production,
/// `ManualWatcher` in tests. A watcher only says "something in the folder changed"; `IngestService` then rescans it.
public protocol FileWatcher: Sendable {
  /// Starts watching `directory` and yields once per batch of changes, with the paths the system named (possibly
  /// none). Throws when the watch cannot start. Stops when the caller stops iterating.
  func changes(in directory: URL) throws -> AsyncStream<[String]>
}

/// The fallback when FSEvents cannot start (06 failure table): a rescan every `interval` (30 s).
public struct PollingWatcher<C: Clock>: FileWatcher where C.Duration == Duration {
  public let clock: C
  public let interval: Duration

  public init(clock: C, interval: Duration = .seconds(30)) {
    self.clock = clock
    self.interval = interval
  }

  public func changes(in directory: URL) throws -> AsyncStream<[String]> {
    let (stream, continuation) = AsyncStream.makeStream(of: [String].self, bufferingPolicy: .bufferingNewest(1))
    let clock = clock
    let interval = interval
    let task = Task {
      while !Task.isCancelled {
        do {
          try await clock.sleep(for: interval)
        } catch {
          // Cancelled: the caller stopped watching, which ends the stream; nothing failed.
          break
        }
        continuation.yield([])
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }
}
