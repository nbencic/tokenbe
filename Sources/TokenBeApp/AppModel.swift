import Foundation
import Observation
import TokenBeCore

/// What the menu bar and popover show (14 § Stage 1.1). Value types only; Core computes them (04 I3).
@Observable @MainActor
final class AppModel {
  var accounts: [AccountSummary] = []
  var isPaused = false
  var isOffline = false
  var lastRefreshAt: Date?
  private(set) var popoverIsOpen = false
  /// Set by `Startup` once the logging step has run.
  var environment: AppEnvironment?

  @ObservationIgnored private let popover = PopoverTracker()

  /// 08 § Menu bar glyph. Stage 1.1: always solid; stale/offline (4.2) and low/critical (5.5) wire the others.
  var glyphState: GlyphState { .solid }

  func popoverDidOpen() {
    popoverIsOpen = true
    popover.opened()
  }

  func popoverDidClose() {
    popoverIsOpen = false
    popover.closed()
  }
}
