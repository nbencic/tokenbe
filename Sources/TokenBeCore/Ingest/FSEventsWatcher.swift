import CoreServices
import Foundation
import Synchronization

/// The production `FileWatcher` (04, 06 § Tailing step 2): an FSEvents stream on the ingest folder, latency 1.0 s,
/// flags `FileEvents | UseCFTypes | NoDefer`.
///
/// FSEvents delivers on a dispatch queue or a run loop; the run-loop call is deprecated. The stream uses the main
/// queue, and its callback does nothing but hand the paths to an `AsyncStream`, so no app logic runs on a dispatch
/// queue (R6 forbids that; Q-049).
public struct FSEventsWatcher: FileWatcher {
  public enum WatchError: Error, Equatable {
    case couldNotCreate
    case couldNotStart
  }

  public let latency: TimeInterval

  public init(latency: TimeInterval = 1.0) {
    self.latency = latency
  }

  public func changes(in directory: URL) throws -> AsyncStream<[String]> {
    let (stream, continuation) = AsyncStream.makeStream(of: [String].self, bufferingPolicy: .bufferingNewest(64))
    let sink = PathSink(continuation: continuation)
    var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(sink).toOpaque(), retain: nil,
                                       release: nil, copyDescription: nil)
    let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
      guard let info else { return }
      let sink = Unmanaged<PathSink>.fromOpaque(info).takeUnretainedValue()
      sink.continuation.yield(unsafeBitCast(paths, to: NSArray.self) as? [String] ?? [])
    }
    let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                           | kFSEventStreamCreateFlagNoDefer)
    guard let ref = FSEventStreamCreate(nil, callback, &context, [directory.path] as CFArray,
                                        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
      throw WatchError.couldNotCreate
    }
    FSEventStreamSetDispatchQueue(ref, DispatchQueue.main)
    guard FSEventStreamStart(ref) else {
      FSEventStreamInvalidate(ref)
      FSEventStreamRelease(ref)
      throw WatchError.couldNotStart
    }
    let handle = StreamHandle(ref: ref, sink: sink)
    continuation.onTermination = { _ in handle.stop() }
    return stream
  }

  /// The callback's context: only the continuation, which is Sendable.
  final class PathSink: Sendable {
    let continuation: AsyncStream<[String]>.Continuation

    init(continuation: AsyncStream<[String]>.Continuation) {
      self.continuation = continuation
    }
  }

  /// Owns the stream: stopped, invalidated and released exactly once. Keeps the sink alive until then.
  final class StreamHandle: Sendable {
    private let ref: Mutex<FSEventStreamRef?>
    private let sink: PathSink

    init(ref: sending FSEventStreamRef, sink: PathSink) {
      self.ref = Mutex(ref)
      self.sink = sink
    }

    func stop() {
      ref.withLock { value in
        guard let stream = value else { return }
        value = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
      }
      sink.continuation.finish()
    }
  }
}
