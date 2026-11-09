import Synchronization

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

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let id = state.withLock { current in
      current.nextID += 1
      return current.nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, any Error>) in
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

  /// Waits (bounded) until `count` tasks are sleeping on this clock.
  func waitForSleepers(_ count: Int = 1) async {
    for _ in 0..<10_000 {
      if sleeperCount >= count { return }
      await Task.yield()
    }
  }
}
