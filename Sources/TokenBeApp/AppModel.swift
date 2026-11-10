import AppKit
import Foundation
import Observation
import SwiftUI
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

  // Settings the popover, the glyph and every scene follow (14 § Stage 1.3 step 5), kept current from
  // `Settings.changes` by `bind(_:)`.
  private(set) var appearance = Appearance.system
  private(set) var useSystemAccent = true
  private(set) var menuBarMetric = "minRunway"
  private(set) var sort = "runway"

  /// Opens the Dashboard window. Captured from the menu-bar label's environment, the only SwiftUI view that exists
  /// from launch, so the global shortcut can open a scene (Q-023).
  @ObservationIgnored var openDashboard: (@MainActor () -> Void)?

  @ObservationIgnored private let popover = PopoverTracker()
  @ObservationIgnored private var settingsWatcher: Task<Void, Never>?

  /// 08 § Menu bar glyph. Stage 1.1: always solid; stale/offline (4.2) and low/critical (5.5) wire the others.
  var glyphState: GlyphState { .solid }

  /// The accent every scene uses (09 `tb.ui.useSystemAccent`): nil follows the system accent colour, otherwise
  /// the fixed `AccentColor` token from the asset catalog (08), light and dark variants.
  var accentTint: Color? { useSystemAccent ? nil : Color(.accent) }

  /// Cards in the order of `tb.popover.sort` (manual uses `tb.popover.manualOrder`).
  var sortedAccounts: [AccountSummary] {
    AccountOrder.sorted(accounts, by: AccountOrder.Sort(rawValue: sort) ?? .runway,
                        manualOrder: environment?.settings.popoverManualOrder ?? [])
  }

  /// Follows the settings that change how the app looks or orders cards, now and on every change.
  func bind(_ settings: TokenBeCore.Settings) {
    apply(settings)
    let changes = settings.changes
    settingsWatcher?.cancel()
    settingsWatcher = Task { [weak self] in
      for await key in changes where Self.watchedKeys.contains(key) {
        self?.apply(settings)
      }
    }
  }

  private static let watchedKeys: Set<SettingsKey> = [.uiAppearance, .uiUseSystemAccent, .menubarMetric, .popoverSort]

  private func apply(_ settings: TokenBeCore.Settings) {
    appearance = Appearance(rawValue: settings.uiAppearance) ?? .system
    useSystemAccent = settings.uiUseSystemAccent
    menuBarMetric = settings.menubarMetric
    sort = settings.popoverSort
    // 09 `tb.ui.appearance`: every scene, the popover included, follows the app's appearance (Q-023).
    NSApp.appearance = appearance.nsAppearance
  }

  func popoverDidOpen() {
    popoverIsOpen = true
    popover.opened()
  }

  func popoverDidClose() {
    popoverIsOpen = false
    popover.closed()
  }
}

/// `tb.ui.appearance` (09).
enum Appearance: String {
  case system, light, dark

  var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}
