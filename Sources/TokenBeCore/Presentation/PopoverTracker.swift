/// Logs popover sessions (07): `ui.popover_open` when shown and `ui.popover_close {dur_ms}` when hidden.
/// Both are `debug` records. Repeated open or close calls (SwiftUI may deliver them twice) are ignored.
@MainActor
public final class PopoverTracker {
  private let clock: ContinuousClock
  private let pipeline: LogPipeline?
  private var openedAt: ContinuousClock.Instant?

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(clock: ContinuousClock = ContinuousClock(), logPipeline: LogPipeline? = nil) {
    self.clock = clock
    self.pipeline = logPipeline
  }

  public var isOpen: Bool { openedAt != nil }

  public func opened() {
    guard openedAt == nil else { return }
    openedAt = clock.now
    emit(.uiPopoverOpen, msg: "popover opened", ctx: [:])
  }

  public func closed() {
    guard let start = openedAt else { return }
    openedAt = nil
    let open = start.duration(to: clock.now)
    emit(.uiPopoverClose, msg: "popover closed", dur: open, ctx: ["dur_ms": .int(LogPipeline.milliseconds(open))])
  }

  private func emit(_ evt: Evt, msg: String, dur: Duration? = nil, ctx: [String: LogValue]) {
    if let pipeline {
      pipeline.emit(.debug, evt, cat: .ui, msg: msg, dur: dur, ctx: ctx)
    } else {
      Log.debug(evt, cat: .ui, msg: msg, dur: dur, ctx: ctx)
    }
  }
}
