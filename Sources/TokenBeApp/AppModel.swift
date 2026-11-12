import AppKit
import Foundation
import Observation
import SwiftUI
import TokenBeCore

/// What the menu bar and popover show (14 § Stage 1.1). Value types only; Core computes them (04 I3).
@Observable @MainActor
final class AppModel {
  var accounts: [AccountSummary] = []
  /// From the coordinator's `CoordinatorState` (14 § Stage 4.1 step 5).
  private(set) var pausedUntil: Date?
  private(set) var inFlightCount = 0
  var isOffline = false
  var isPaused: Bool { pausedUntil != nil }
  /// The header's `Refreshed …`: the oldest of the accounts' last successes (Core, `AccountSummary.refreshedAt`).
  var lastRefreshAt: Date? { AccountSummary.refreshedAt(accounts) }
  private(set) var popoverIsOpen = false
  /// Set by `Startup` once the logging step has run.
  var environment: AppEnvironment?

  // Settings the popover, the glyph and every scene follow (14 § Stage 1.3 step 5), kept current from
  // `Settings.changes` by `bind(_:)`.
  private(set) var appearance = Appearance.system
  private(set) var useSystemAccent = true
  private(set) var menuBarMetric = "minRunway"
  private(set) var sort = "runway"

  /// The `account` rows behind `accounts`, for the Accounts tab's edits (label, paused, remove).
  private(set) var records: [AccountRecord] = []
  /// Keychain refs with no item (04 startup step 3); cleared for an account once its key is replaced.
  var missingKeys: Set<String> = [] {
    didSet { rebuild() }
  }
  /// The Settings tab to show; `Key missing · Fix…` selects Accounts (08).
  var settingsTab = SettingsTab.general
  @ObservationIgnored private var lastInputs = SummaryInputs(accounts: [])

  /// Opens the Dashboard window. Captured from the menu-bar label's environment, the only SwiftUI view that exists
  /// from launch, so the global shortcut can open a scene (Q-023).
  @ObservationIgnored var openDashboard: (@MainActor () -> Void)?
  /// Opens the onboarding window, captured the same way (Q-030).
  @ObservationIgnored var openOnboarding: (@MainActor () -> Void)? {
    didSet {
      if onboardingPending, let openOnboarding {
        onboardingPending = false
        openOnboarding()
      }
    }
  }
  @ObservationIgnored private var onboardingPending = false

  /// 09 `tb.ui.onboardingDone`: at launch, onboarding opens when it is false and there is no account. Also
  /// `Add account…` in the Empty state (08).
  func showOnboarding() {
    guard let openOnboarding else {
      onboardingPending = true
      return
    }
    NSApp.activate()
    openOnboarding()
  }

  @ObservationIgnored private let popover = PopoverTracker()
  @ObservationIgnored private var settingsWatcher: Task<Void, Never>?
  @ObservationIgnored private var summaryWatcher: Task<Void, Never>?
  @ObservationIgnored private var coordinatorWatcher: Task<Void, Never>?

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

  /// Keeps `accounts` current from the database (14 § Stage 2.2): `ValueObservation` through the repository, mapped
  /// by Core's `AccountSummaryBuilder` (04 I2, I3). A row Core cannot read is left out and logged `ui.error`.
  func observe(_ repository: any Repository) {
    let inputs = repository.observeSummaryInputs()
    summaryWatcher?.cancel()
    summaryWatcher = Task { [weak self] in
      for await next in inputs {
        self?.lastInputs = next
        self?.rebuild()
      }
    }
  }

  /// Follows the scheduler: pause, jobs in flight, reachability.
  func observe(_ coordinator: PollCoordinator<ContinuousClock>) {
    let states = coordinator.states
    coordinatorWatcher?.cancel()
    coordinatorWatcher = Task { [weak self] in
      for await state in states {
        self?.pausedUntil = state.pausedUntil
        self?.inFlightCount = state.inFlightCount
        self?.isOffline = !state.isOnline
      }
    }
  }

  /// The header's refresh button (08): every account's jobs, now.
  func refreshNow() {
    guard let coordinator = environment?.coordinator else { return }
    Task { await coordinator.refreshNow() }
  }

  /// `Pause polling for 1 h` (08): 09 `tb.poll.pausedUntil = now + 3600`.
  func pauseForOneHour() {
    environment?.settings.pollPausedUntil = Date().addingTimeInterval(Self.pauseDuration).timeIntervalSince1970
  }

  /// `Resume` (08): 09 `tb.poll.pausedUntil = 0`.
  func resume() {
    environment?.settings.pollPausedUntil = 0
  }

  static let pauseDuration: TimeInterval = 3600

  private func rebuild() {
    records = lastInputs.accounts
    accounts = AccountSummaryBuilder.summaries(from: lastInputs, missingKeys: missingKeys) { record, invalid in
      Log.error(.uiError, cat: .ui, msg: "account row skipped", acct: record.id, err: invalid, ctx: [
        "view": "accounts"
      ])
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

/// The Settings window's tabs, in Paper's order (08 § Settings).
enum SettingsTab: Hashable {
  case general, accounts, sources, privacy, advanced
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
