/// Runs the latest submitted action once no newer one arrived for `delay` (the Dashboard frame save, 14 § 1.2:
/// 500 ms). Each `submit` cancels the pending one. The clock is injected so tests advance time by hand.
@MainActor
public final class Debouncer<C: Clock> where C.Duration == Duration {
  private let delay: Duration
  private let clock: C
  private var pending: Task<Void, Never>?

  public init(delay: Duration, clock: C) {
    self.delay = delay
    self.clock = clock
  }

  public func submit(_ action: @escaping @MainActor () -> Void) {
    pending?.cancel()
    pending = Task { [delay, clock] in
      do {
        try await clock.sleep(for: delay)
      } catch {
        return  // Cancelled by a newer submit: expected, nothing to log.
      }
      guard !Task.isCancelled else { return }
      action()
    }
  }

  /// Runs nothing that is pending (window closed or app terminating after a final explicit save).
  public func cancel() {
    pending?.cancel()
    pending = nil
  }
}
