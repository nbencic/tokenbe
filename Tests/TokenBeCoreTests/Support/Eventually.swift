import Testing

/// Waits until `condition` holds, yielding to other tasks; bounded by real time (default 5 s), not by a yield
/// count, because a loaded parallel run can starve a task for thousands of yields. Records an issue on timeout.
func eventually(_ what: String, timeout: Duration = .seconds(5), sourceLocation: SourceLocation = #_sourceLocation,
                _ condition: @Sendable () async -> Bool) async {
  let giveUp = ContinuousClock.now + timeout
  while await !condition() {
    if ContinuousClock.now >= giveUp {
      Issue.record("timed out waiting for \(what)", sourceLocation: sourceLocation)
      return
    }
    await Task.yield()
  }
}
