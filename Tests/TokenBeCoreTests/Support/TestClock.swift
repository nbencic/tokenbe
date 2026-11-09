import Synchronization
import Testing

/// Manual clock (11 § helpers): time moves only through `advance(by:)`; sleepers wake when their deadline passes.
final class TestClock: Clock, Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }

  private struct Sleeper {
    let id: Int
    let deadline: Instant
    let resume: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var now = Instant(offset: .zero)
    var sleepers: [Sleeper] = []
    var nextID = 0
  }

  private let state = Mutex(State())

  var now: Instant { state.withLock { $0.now } }
  var minimumResolution: Duration { .zero }
  var sleeperCount: Int { state.withLock { $0.sleepers.count } }
  /// The pending sleepers' deadlines as offsets from the clock's start, earliest first.
  var deadlines: [Duration] { state.withLock { $0.sleepers.map(\.deadline.offset).sorted() } }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let id = state.withLock { current in
      current.nextID += 1
      return current.nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, any Error>) in
        // Like a real clock, an already-cancelled task never registers a sleeper (its cancellation handler
        // has already run and would find nothing to remove).
        if Task.isCancelled {
          resume.resume(throwing: CancellationError())
          return
        }
        let immediate: Bool = state.withLock { current in
          if deadline <= current.now { return true }
          current.sleepers.append(Sleeper(id: id, deadline: deadline, resume: resume))
          return false
        }
        if immediate { resume.resume() }
      }
    } onCancel: {
      let cancelled = state.withLock { current -> Sleeper? in
        guard let index = current.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
        return current.sleepers.remove(at: index)
      }
      cancelled?.resume.resume(throwing: CancellationError())
    }
  }

  func advance(by duration: Duration) {
    let due = state.withLock { current -> [Sleeper] in
      current.now = current.now.advanced(by: duration)
      let ready = current.sleepers.filter { $0.deadline <= current.now }
      current.sleepers.removeAll { $0.deadline <= current.now }
      return ready
    }
    for sleeper in due { sleeper.resume.resume() }
  }

  /// Waits until `count` tasks are sleeping on this clock.
  func waitForSleepers(_ count: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) async {
    await waitUntil("\(count) sleeper(s)", sourceLocation: sourceLocation) { $0.sleeperCount >= count }
  }

  /// Waits until `condition` holds, yielding to other tasks. Bounded by 5 s of real time, not by a yield count:
  /// under a loaded parallel test run thousands of yields can pass before another task is scheduled. A timeout
  /// is recorded as a test issue instead of returning silently.
  func waitUntil(_ what: String, sourceLocation: SourceLocation = #_sourceLocation,
                 _ condition: @Sendable (TestClock) -> Bool) async {
    await eventually(what, sourceLocation: sourceLocation) { condition(self) }
  }
}
