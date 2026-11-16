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
  /// From `CoordinatorState`: the stale threshold stretches with Low Power, and the Sources strip shows next runs.
  private(set) var isLowPower = false
  private(set) var nextDue: [String: [Job: Date]] = [:]
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
  /// Every `ledger_event` row, oldest first, for the account page's ledger list (08 § Account detail 7).
  private(set) var ledgerEvents: [LedgerEventRecord] = []
  /// `band_state` as observed, for the glyph before an account's first poll (04 step 8).
  private(set) var bandStates: [BandStateRecord] = []
  /// Apps, their bindings and the provider keys, as observed (14 § Stage 7.1): Keys & apps and the Apps page.
  private(set) var apps: [AppRecord] = []
  private(set) var bindings: [AppBindingRecord] = []
  private(set) var providerKeys: [ProviderKeyRecord] = []
  /// Settings → Sources → Harness reports (08, 14 § Stage 7.2): the ingest service's status.
  private(set) var ingestStatus = IngestStatus()
  /// Harness lines stored for a provider with no account (O-12).
  private(set) var harnessWithoutAccount = 0
  /// Keychain refs with no item (04 startup step 3); cleared for an account once its key is replaced.
  var missingKeys: Set<String> = [] {
    didSet { rebuild() }
  }
  /// The Settings tab to show; `Key missing · Fix…` selects Accounts (08).
  var settingsTab = SettingsTab.general
  /// The Dashboard's sidebar selection; a popover card selects its account (08: card click → account detail).
  var dashboardSelection: SidebarView.Item? = .overview
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
  @ObservationIgnored private var pricesWatcher: Task<Void, Never>?
  @ObservationIgnored private var ingestWatcher: Task<Void, Never>?
  /// The price book's rates, for the unpriced estimate (05 `unpriced_cents`).
  @ObservationIgnored private var pricer = Pricer()
  /// Writes `band_state` and logs `ui.band_change` when an evaluated band changes (14 § Stage 5.3 step 2).
  @ObservationIgnored private var bands: BandRecorder?
  /// The user denied notifications (O-11: the Alerts tab shows a banner); nil before the first alert.
  private(set) var notificationsAllowed: Bool?
  /// Sleeps until the next account turns stale, then rebuilds (stale needs no database write, 14 § Stage 4.2).
  @ObservationIgnored private var staleWatcher: Task<Void, Never>?

  /// 08 § Menu bar glyph (Core `GlyphState`): dashed when any account is stale or the Mac is offline, notched when
  /// any is low or critical, else solid. Until the accounts are observed and polled, the persisted bands decide
  /// (04 step 8).
  var glyphState: GlyphState {
    let persisted = lastInputs.accounts.isEmpty ? environment?.initialBands ?? [] : bandStates
    return GlyphState.state(accounts: accounts, offline: isOffline, persisted: persisted)
  }

  /// The text right of the glyph (09 `tb.menubar.metric`); nil for `none` or before anything is known.
  var menuBarText: String? {
    MenuBarMetric(rawValue: menuBarMetric)?.text(accounts, hideCents: environment?.settings.uiHideCents ?? true,
                                                  locale: .current)
  }

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
      for await key in changes {
        if Self.watchedKeys.contains(key) { self?.apply(settings) }
        if Self.freshnessKeys.contains(key) { self?.rebuild(trigger: .settings) }
      }
    }
  }

  /// Keeps `accounts` current from the database (14 § Stage 2.2): `ValueObservation` through the repository, mapped
  /// by Core's `AccountSummaryBuilder` (04 I2, I3). A row Core cannot read is left out and logged `ui.error`.
  func observe(_ repository: any Repository) {
    let inputs = repository.observeSummaryInputs()
    bands = BandRecorder(store: repository)
    summaryWatcher?.cancel()
    summaryWatcher = Task { [weak self] in
      for await next in inputs {
        self?.lastInputs = next
        self?.rebuild(trigger: .data)
      }
    }
  }

  /// Follows the price book: new rates change the unpriced estimate (14 § Stage 5.2).
  func observe(_ book: PriceBook) {
    pricesWatcher?.cancel()
    pricesWatcher = Task { [weak self] in
      for await status in await book.updates() {
        guard let self, status.pricer != self.pricer else { continue }
        self.pricer = status.pricer
        self.rebuild(trigger: .settings)
      }
    }
  }

  /// Follows the harness drop folder (06): mode, files, last line, today's counters.
  func observe(_ ingest: IngestService) {
    ingestWatcher?.cancel()
    let updates = ingest.statusUpdates()
    ingestWatcher = Task { [weak self] in
      for await status in updates { self?.ingestStatus = status }
    }
  }

  /// Follows the scheduler: pause, jobs in flight, reachability.
  func observe(_ coordinator: PollCoordinator<ContinuousClock>) {
    let states = coordinator.states
    coordinatorWatcher?.cancel()
    coordinatorWatcher = Task { [weak self] in
      for await state in states {
        self?.apply(state)
      }
    }
  }

  private func apply(_ state: CoordinatorState) {
    pausedUntil = state.pausedUntil
    inFlightCount = state.inFlightCount
    isOffline = !state.isOnline
    guard state.isLowPower != isLowPower || state.nextDue != nextDue else { return }
    isLowPower = state.isLowPower
    nextDue = state.nextDue
    rebuild()
  }

  /// The popover's refresh button (every account) and the Dashboard's `Refresh` (the account shown, 08): the jobs
  /// run now, within the scheduler's skip rules.
  func refreshNow(_ accountID: String? = nil) {
    guard let coordinator = environment?.coordinator else { return }
    Task { await coordinator.refreshNow(accountID) }
  }

  /// A popover card (08): the Dashboard, on that account's page.
  func showAccount(_ id: String) {
    dashboardSelection = .account(id)
    openDashboard?()
    NSApp.activate()
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

  /// `New app…` (Keys & apps) and `Name…` (By-app table, 08): a new app, bound to the key in the same write (R7).
  func createApp(_ displayName: String, binding key: ProviderKeyRef) {
    appsWrite("app not created", acct: key.accountID) { repository in
      _ = try await repository.upsertApp(displayName: displayName, binding: key)
    }
  }

  /// The Apps page: a new display name (O-13: the name, the harness tag, never changes).
  func renameApp(_ id: String, to displayName: String) {
    appsWrite("app not renamed", acct: nil) { try await $0.upsertApp(id: id, displayName: displayName) }
  }

  /// Keys & apps `Bound app`: binds the key to the app, or unbinds it for `—`.
  func bind(_ key: ProviderKeyRef, to appID: String?) {
    appsWrite("binding not saved", acct: key.accountID) { repository in
      if let appID {
        try await repository.bind(appID: appID, key: key)
      } else {
        try await repository.unbind(key: key)
      }
    }
  }

  /// Runs an app write; a failure logs `ui.error {view: apps}` and changes nothing (the observation shows the truth).
  private func appsWrite(_ msg: String, acct: String?, _ write: @escaping @Sendable (any Repository) async throws -> Void) {
    guard let repository = environment?.repository else { return }
    Task {
      do {
        try await write(repository)
      } catch {
        Log.error(.uiError, cat: .ui, msg: msg, acct: acct, err: error, ctx: ["view": "apps"])
      }
    }
  }

  /// `trigger` says why (a database change, a setting, time passing); `ui.band_change` carries it (Q-042).
  private func rebuild(trigger: BandRecorder.Trigger = .clock) {
    if records != lastInputs.accounts { records = lastInputs.accounts }
    if ledgerEvents != lastInputs.ledgerEvents { ledgerEvents = lastInputs.ledgerEvents }
    if bandStates != lastInputs.bandStates { bandStates = lastInputs.bandStates }
    if apps != lastInputs.apps { apps = lastInputs.apps }
    if bindings != lastInputs.bindings { bindings = lastInputs.bindings }
    if providerKeys != lastInputs.providerKeys { providerKeys = lastInputs.providerKeys }
    if harnessWithoutAccount != lastInputs.harnessWithoutAccount { harnessWithoutAccount = lastInputs.harnessWithoutAccount }
    let settings = environment?.settings
    let range = DashboardRange(setting: settings?.uiDashboardRange ?? DashboardRange.default.rawValue)
    let now = Date()
    let spend = AccountSummaryBuilder.SpendContext(range: range, now: now, pricer: pricer,
                                                   thresholds: settings.map(BandThresholds.init) ?? BandThresholds())
    var next = AccountSummaryBuilder.summaries(from: lastInputs, missingKeys: missingKeys, spend: spend) { record, invalid in
      Log.error(.uiError, cat: .ui, msg: "account row skipped", acct: record.id, err: invalid, ctx: [
        "view": "accounts"
      ])
    }
    let flip = Freshness.apply(to: &next, context: freshnessContext, now: now)
    if accounts != next { accounts = next }
    if let bands, let environment {
      let evaluated = next
      let persisted = lastInputs.bandStates
      let alerts = environment.alerts
      let alertSettings = AlertSettings(environment.settings)
      Task { [weak self] in
        let transitions = await bands.record(evaluated, persisted: persisted, trigger: trigger, now: now)
        await alerts.process(evaluated, transitions: transitions, settings: alertSettings, now: now)
        let allowed = await alerts.isAuthorized
        if self?.notificationsAllowed != allowed { self?.notificationsAllowed = allowed }
      }
    }
    rebuild(at: flip)
  }

  /// 05: stale past `tb.alerts.staleMultiplier` × the interval the scheduler uses (09 settings, the account's
  /// override, Low Power).
  private var freshnessContext: FreshnessContext {
    guard let settings = environment?.settings else { return FreshnessContext(lowPower: isLowPower, nextDue: nextDue) }
    return FreshnessContext(settings: ScheduleSettings(settings), staleMultiplier: settings.alertsStaleMultiplier,
                            lowPower: isLowPower, nextDue: nextDue)
  }

  /// Rebuilds once `flip` has passed (a second late, so it is strictly past the threshold). No Timer (R6).
  private func rebuild(at flip: Date?) {
    staleWatcher?.cancel()
    guard let flip else { return }
    let delay = max(0, flip.timeIntervalSinceNow) + 1
    staleWatcher = Task { [weak self] in
      do {
        try await ContinuousClock().sleep(for: .seconds(delay))
      } catch {
        // Cancelled by a newer rebuild: a control signal, not a failure, so there is nothing to log.
        return
      }
      self?.rebuild()
    }
  }

  private static let watchedKeys: Set<SettingsKey> = [.uiAppearance, .uiUseSystemAccent, .menubarMetric, .popoverSort,
                                                      .uiHideCents]
  /// Keys the stale threshold reads (09 `tb.alerts.staleMultiplier`, § Sources).
  /// … and the range the numbers strip and the Overview subline sum over (09 `tb.ui.dashboardRange`).
  /// `Send test notification` (Alerts tab): false when it could not be sent (denied, or the system refused).
  func sendTestNotification() async -> Bool {
    guard let alerts = environment?.alerts else { return false }
    let sent = await alerts.sendTest(sortedAccounts.first)
    notificationsAllowed = await alerts.isAuthorized
    return sent
  }

  /// … and the Alerts thresholds the bands use (09).
  private static let freshnessKeys: Set<SettingsKey> = ScheduleSettings.keys.union([.alertsStaleMultiplier,
                                                                                    .uiDashboardRange])
    .union(BandThresholds.keys).union(AlertSettings.keys)

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
  case general, accounts, sources, alerts, privacy, advanced
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
