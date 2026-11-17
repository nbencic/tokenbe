import Foundation
import TokenBeCore

// R9 keeps every string in this one file, so it outgrows SwiftLint's 400 lines (Q-048).
// swiftlint:disable file_length
/// Every user-visible string (12 § R9, 08), exactly as 08 writes it. Views never contain inline copy.
enum Strings {
  static let appName = "TokenBe"

  // Popover — Empty state (08 § Popover states)
  static let emptyHeadline = "No accounts yet"
  static let emptyBody = "Add a provider key to start tracking."

  static let addAccount = "Add account\u{2026}"

  // Popover — cards (08 § Popover, § Popover states)
  static let noDataYet = "No data yet"
  static let keyMissingFix = "Key missing \u{00B7} Fix\u{2026}"
  static let modeAnchored = "\u{2248}"
  static let modeSpendOnly = "spend"
  /// Day-1 collecting (08 § Popover states, `1XL-0`).
  static let collecting = "Collecting\u{2026} runway after 2 days of data"
  /// 05: auto-reload on and remaining at or below its threshold.
  static func reloadsAt(_ amount: String) -> String { "reloads at \(amount)" }
  /// Row 3 of a spend-only card (08): `today $3.10 · 30 d $84`; also the `todaySpend` metric outside row 2.
  static func todaySpend(_ amount: String) -> String { "today \(amount)" }
  static func spend30d(_ amount: String) -> String { "30 d \(amount)" }

  // Popover — alert banner (08 § Popover 2)
  static func bannerRunway(_ runway: String) -> String { ": \(runway) left" }
  static let bannerSetAnchor = ": set an anchor to see runway"
  /// A critical band forced by the provider (D-deepseek-unavailable) has no runway to show; authored (Q-045).
  static let bannerUnavailable = ": account unavailable"

  // Popover — footer (08 § Popover 4)
  static func refreshed(_ freshness: String) -> String { "Refreshed \(freshness)" }
  static let refresh = "Refresh"
  static func pausedResumes(_ time: String) -> String { "Paused \u{00B7} resumes \(time)" }
  static let resume = "Resume"
  static let pausePolling = "Pause polling for 1 h"
  static let openDashboard = "Open dashboard"
  static let settingsEllipsis = "Settings\u{2026}"
  static let quit = "Quit"

  // Dashboard window (08 § Dashboard window, 14 § Stage 1.2)
  static let dashboardTitle = "Dashboard"
  static let overview = "Overview"
  static let spendByDay = "Spend by day"
  static let noSpendInRange = "No spend in this range"
  static let rangePicker = "Range"
  static let rangeToday = "Today"
  static let range7d = "7 d"
  static let range30d = "30 d"
  static let range90d = "90 d"

  // Account page numbers strip (08 § Account detail 3; 14 § Stage 5.2 step 4) and the Overview subline
  static let spendToday = "Spend today"
  static let spendInRange = "Spend in range"
  static let unpricedInRange = "Unpriced in range"
  /// `Total spend 7 d ≈ $12.40 + 1 non-USD` (05 § Currency: USD accounts only).
  static func totalSpend(range: String, amount: String, nonUSD: Int) -> String {
    "Total spend \(range) \(amount)" + (nonUSD > 0 ? " + \(nonUSD) non-USD" : "")
  }

  // Settings window (08 § Settings, 09; 14 § Stage 1.3)
  static let tabGeneral = "General"
  static let tabAccounts = "Accounts"
  static let tabSources = "Sources"
  static let tabPrivacy = "Privacy"
  static let tabAdvanced = "Advanced"
  static let launchAtLogin = "Launch at login"
  static let menuBarGlyph = "Menu bar glyph"
  static let glyphRing = "Ring"
  static let menuBarMetric = "Menu bar metric"
  static let metricNone = "None"
  static let metricMinRunway = "Shortest runway"
  static let metricMinRemaining = "Lowest remaining"
  static let metricTodaySpend = "Today\u{2019}s spend"
  static let pinnedMetric = "Pinned metric"
  static let pinnedRunway = "Runway"
  static let pinnedRemaining = "Remaining"
  static let sort = "Sort"
  static let sortRunway = "Runway"
  static let sortRemaining = "Remaining"
  static let sortName = "Name"
  static let sortManual = "Manual"
  static let currencyDisplay = "Currency display"
  static let currencyNative = "USD"
  static let currencyCaption = "Conversion is not in v1"
  static let hideCents = "Hide cents"
  static let appearance = "Appearance"
  static let appearanceSystem = "System"
  static let appearanceLight = "Light"
  static let appearanceDark = "Dark"
  static let useSystemAccent = "Use system accent color"
  static let globalShortcut = "Global shortcut"
  static let shortcutNone = "None"
  static let shortcutRecording = "Type shortcut\u{2026}"
  static let shortcutHelp = "Click, then press a key with \u{2303}, \u{2325}, \u{21E7} or \u{2318}. \u{232B} clears, Esc cancels."
  static let privacyKeys = "API keys are stored in your macOS Keychain and are sent only to the provider they belong to."
  static let privacyTelemetry = "TokenBe has no telemetry. Logs stay on this Mac."
  static let openLogFolder = "Open log folder"
  static let logLevel = "Log level"
  static let logLevelDebug = "Debug"
  static let logLevelInfo = "Info"
  static let logLevelWarn = "Warning"
  static let logLevelError = "Error"
  static let logRetention = "Log retention"
  static func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }
  static let runIntegrityCheckNow = "Run integrity check now"
  static let backUpNow = "Back up now"

  // Result sheets of the two maintenance buttons (14 § Stage 2.2). 08 names only the buttons (Q-025).
  static let integrityCheckTitle = "Integrity check"
  static func integrityResult(_ result: String) -> String { "Result: \(result)" }
  static func corruptCopy(_ path: String) -> String { "A copy of the database was saved to \(path)" }
  static let backupTitle = "Backup saved"
  static func backupDetail(size: String, time: String) -> String { "\(size), \(time)" }
  static let backupFailedTitle = "Backup failed"
  static let integrityCheckFailedTitle = "Integrity check could not run"

  /// VoiceOver label for a band dot (08 § Accessibility: colour is never the only carrier).
  static func bandLabel(_ word: String) -> String { "Band: \(word)" }

  // Database alerts (03 § Migrations, § Durability; 14 § Stage 2.1). 08 has no copy for these (Q-024).
  static let databaseFatalTitle = "TokenBe can\u{2019}t open its database"
  static func databaseFatalBody(migration: String?, error: String, database: String, backup: String) -> String {
    let cause = migration.map { "Migration \($0) failed." } ?? "The database could not be opened."
    return "\(cause)\n\nError: \(error)\n\nYour data has not been changed.\nDatabase: \(database)\nBackup: \(backup)"
  }
  static let databaseRecoveredTitle = "TokenBe repaired its database"
  static func databaseRecoveredBody(corruptCopy: String, restoredFrom: String?) -> String {
    guard let restoredFrom else {
      return "The database was damaged and no backup was found, so TokenBe started a new, empty database."
        + "\n\nDamaged copy: \(corruptCopy)"
    }
    return "The database was damaged and has been restored from the last backup."
      + "\n\nDamaged copy: \(corruptCopy)\nBackup used: \(restoredFrom)"
  }
  static let okButton = "OK"

  // Onboarding (08 § Onboarding). The step header, titles and field labels come from Paper `LZ-0`/`I4-0`/`JV-0`,
  // where 08 has no copy (Q-030); the captions, buttons and messages are 08's.
  static let onboardingTitle = "Add account"
  static let stepProvider = "Provider"
  static let stepKey = "Key"
  static let stepResult = "Balance"
  static let whichProvider = "Which provider?"
  static let captionOpenAI = "Admin key required"
  static let captionAnthropic = "Needs an Organization"
  static let captionOpenRouter = "Management key"
  static let captionBalanceOnly = "Balance only \u{00B7} apps via harness"
  static let added = "Added"
  static let continueButton = "Continue"
  static let back = "Back"
  static func keyTitle(_ provider: String) -> String { "\(provider) admin key" }
  static let apiKeyLabel = "Admin API key"
  static let accountLabel = "Label"
  static let paste = "Paste"
  static let keychainNote = "Stored in the macOS Keychain, this device only."
  static let wrongPrefixOpenAI = "This looks like a project key. TokenBe needs an Admin key (sk-admin-\u{2026})."
  static func wrongPrefix(_ expected: String) -> String { "TokenBe needs a key that starts with \(expected)\u{2026}" }
  static let testAndContinue = "Test & continue"
  static let firstNumbers = "First numbers"
  static let modeLabel = "Mode"
  static let keyCountLabel = "Keys found"
  static let currencyLabel = "Currency"
  static let modeDirect = "direct"
  static let modeAnchoredWord = "anchored"
  static let modeSpendOnlyWord = "spend_only"
  static let anchorAmount = "Balance shown by the provider"
  static let setAnchor = "Set anchor\u{2026}"
  static let skipForNow = "Skip for now"
  static let done = "Done"
  static func anchorSaved(_ amount: String) -> String { "Anchor: \(amount)" }
  static let anchorFailed = "The anchor was not saved. Try again."
  static let accountCreateFailed = "TokenBe could not save this account. The key was not stored."

  // Settings → Accounts (08 § Settings, Paper `14Z-0`; 14 § Stage 3.5 step 2)
  static func keyValid(_ freshness: String) -> String { "Valid \u{00B7} tested \(freshness)" }
  static let keyMissing = "Key missing"
  static let replaceKey = "Replace key\u{2026}"
  static let keyReplaceFailed = "TokenBe could not store the new key. The old key is unchanged."
  static let test = "Test"
  static let removeAccount = "Remove account\u{2026}"
  static func removeAccountQuestion(_ label: String) -> String { "Remove \(label)?" }
  static let removeAccountDetail = "TokenBe deletes the key from the Keychain and this account\u{2019}s data from its database."
  static let remove = "Remove"
  static let paused = "Paused"
  static let keysAndApps = "Keys & apps"
  static let keyName = "Name"
  static let keyHint = "Hint"
  static let unnamedKey = "(unnamed key)"
  static let noKeysYet = "No keys found yet."
  static let noAccountSelected = "Select an account."
  static func hint(_ last4: String) -> String { "\u{2026}\(last4)" }

  // Settings → Sources (08 § Settings; labels from 14 § Stage 4.1 step 3) and the per-account overrides (Q-034).
  static let refreshIntervals = "Refresh intervals"
  static let balanceEvery = "Balance every"
  static let anthropicUsageEvery = "Anthropic usage every"
  static let openAIUsageEvery = "OpenAI usage every"
  static let keysEvery = "Keys every"
  static let usageEvery = "Usage every"
  static let lowPowerMultiplier = "Low Power multiplier"
  static func every(_ label: String, _ interval: String) -> String { "\(label) \(interval)" }
  static func times(_ factor: Int) -> String { "\u{00D7}\(factor)" }
  static let lowPowerCaption = "Intervals are multiplied by this while Low Power Mode is on."
  static func sourcesDefault(_ interval: String) -> String { "Sources setting (\(interval))" }

  // Popover — Offline (08 § Popover states)
  static let offlineBanner = "Offline \u{2014} showing last known values"

  // Account page (08 § Account detail; 14 § Stage 4.2). Badge words are 08's; each help sentence follows 02 (Q-036).
  static func badgeBalance(_ word: String) -> String { "Balance: \(word)" }
  static func badgeUsage(_ word: String) -> String { "Usage: \(word)" }
  static func badgeCost(_ word: String) -> String { "Cost: \(word)" }
  static func badgeLag(_ interval: String) -> String { "Lag: \(interval)" }
  /// Account header chip when the provider reports the account unavailable (13 § D-deepseek-unavailable, 08).
  static let providerUnavailable = "Provider reports account unavailable"
  static let helpBalanceDirect = "The provider reports the balance, so remaining is read directly."
  static let helpBalanceAnchored =
    "There is no balance endpoint, so remaining is your anchor plus top-ups minus spend since the anchor."
  static let helpBalanceNone = "Without an anchor the account is spend only: no remaining and no runway until anchored."
  static let helpUsagePerKey = "Usage is reported per provider key, so apps bound to a key are attributed from provider rows."
  static let helpUsageOrgOnly = "Usage is reported for the whole organization only, so per-app numbers are split estimates."
  static let helpUsageHarness = "There is no usage endpoint; per-app attribution comes only from harness reports."
  static let helpCostProvider =
    "The provider's cost report reconciles to the invoice: cost is the truth, usage \u{00D7} price is an estimate."
  static let helpCostEstimated = "There is no cost endpoint, so spend is estimated as usage \u{00D7} price."
  static func helpLag(_ provider: ProviderID) -> String {
    switch provider {
    case .openai: "Usage buckets less than 60 minutes old are provisional; OpenAI publishes no finalization window."
    case .anthropic: "Usage typically appears within 5 minutes."
    case .openrouter: "Balance and per-key spend update within seconds."
    case .deepseek: "The balance updates within seconds to minutes."
    case .xai: "The balance updates within seconds."
    }
  }

  // Sources strip (08 `HP-0`): `Usage · ok · 2 min ago · next 3 min`, `Cost · ok · 02:10`, `Balance · n/a`.
  static let sourceUsage = "Usage"
  static let sourceCost = "Cost"
  static let sourceBalance = "Balance"
  static let sourceKeys = "Keys"
  static let sourceOK = "ok"
  static let sourceFailed = "failed"
  static let sourceNotApplicable = "n/a"
  static func next(_ interval: String) -> String { "next \(interval)" }
  static func sourceLine(_ parts: [String]) -> String { parts.joined(separator: " \u{00B7} ") }

  // Daily activity (08 § Settings: Sources `Run daily tasks now`, Advanced `Last daily run`; 14 § Stage 4.3)
  static let runDailyTasksNow = "Run daily tasks now"
  static let lastDailyRun = "Last daily run"
  static let never = "never"
  /// `MMM d` (08) plus the time of day, which 08 has no rule for (Q-025).
  static func dateTime(_ date: Date) -> String {
    "\(Formatters.date(date, calendar: .current)) \(date.formatted(date: .omitted, time: .shortened))"
  }

  // Settings → Sources → Price book (08 § Settings; Paper `10V-0`; 14 § Stage 5.1, Q-038)
  static let priceBook = "Price book"
  static let priceFeedTitle = "Refresh rates daily from the LiteLLM price map"
  static let refreshNow = "Refresh now"
  static let priceFeedToggle = "Refresh rates daily"
  /// `Snapshot v2026-11-08 · 412 models · 2 overrides · refreshed 3 h ago · the only other network call`.
  /// `N unpriced` (models with unpriced usage in the last 90 days) appears after the overrides when N > 0 (5.2).
  static func priceSnapshotCaption(version: String?, models: Int, overrides: Int, unpriced: Int = 0,
                                   refreshed: String) -> String {
    let snapshot = version.map { $0.first?.isNumber == true ? "Snapshot v\($0)" : "Snapshot \($0)" } ?? "No snapshot"
    return sourceLine([snapshot, count(models, "model"), count(overrides, "override")]
                      + (unpriced > 0 ? ["\(unpriced) unpriced"] : [])
                      + ["refreshed \(refreshed)", "the only other network call"])
  }
  static let priceStaleAfter = "Stale after"
  static let priceOverridesTitle = "Your overrides win over the feed"
  static let priceOverridesCaption = "Kept across refreshes and exports. Rates in USD per 1M tokens."
  static let priceModel = "Model"
  static let priceInput = "Input"
  static let priceOutput = "Output"
  static let priceCacheRead = "Cache read"
  static let priceCacheWrite = "Cache write"
  static let priceAddOverride = "Add override"
  static let priceRemoveOverride = "Remove override"
  static let resetToFeed = "Reset to feed"
  static let resetToFeedConfirm = "Remove every override and use the feed's rates?"
  static let priceOverrideSheetTitle = "Override a model's rates"
  static let priceOverrideSheetCaption = "USD per 1M tokens. Input and output are required; cache rates are optional."
  static let priceOverrideInvalid = "Enter a model and positive input and output rates."
  static let save = "Save"
  static let priceNoOverrides = "No overrides"
  static let priceFeedURL = "Price feed URL"
  static func count(_ value: Int, _ noun: String) -> String { value == 1 ? "1 \(noun)" : "\(value) \(noun)s" }

  // Sources strip: the price snapshot's chip, `Prices · Nov 8 · ok` (14 § Stage 5.1 step 6)
  static let sourcePrices = "Prices"
  static let sourceStale = "stale"
}

/// Stage 5.3's copy: the numbers strip, Overview headline and board, account page, sheets, Alerts, auto-reload.
extension Strings {
  // Numbers strip (08 § Account detail 3)
  static let remaining = "Remaining"
  static let runway = "Runway"
  static let burn7d = "Burn 7 d"
  static func perDay(_ amount: String) -> String { "\(amount)/day" }

  // Overview headline and runway board (08 § Overview 1–2)
  static func shortestRunway(_ label: String, _ runway: String) -> String { "Shortest runway: \(label) \u{00B7} \(runway)" }
  static func totalRemaining(_ amount: String, usdAccounts: Int, nonUSD: Int) -> String {
    "Total remaining \(amount) across \(usdAccounts) USD account\(usdAccounts == 1 ? "" : "s")"
      + (nonUSD > 0 ? " + \(nonUSD) non-USD" : "")
  }
  static let boardAccount = "Account"
  static let boardRemaining = "Remaining"
  static let boardRunway = "Runway"
  static let boardBurn = "Burn 7 d/day"
  static let boardToday = "Today"
  static let boardFreshness = "Freshness"
  static let boardBand = "Band"

  // Account page: header, nudges, ledger (08 § Account detail 1, 7; 09 `tb.alerts.anchorAgeDays`; Q-042)
  static let addTopUp = "Add top-up\u{2026}"
  static func anchorOld(_ days: Int) -> String { "The anchor is \(days) days old. Set a new one to tighten the estimate." }
  static let reanchor = "Spend has passed the anchor by more than a day. Set a new anchor."
  static let ledger = "Ledger"
  static let ledgerEmpty = "No anchor or top-up yet"
  static let delete = "Delete"
  static func ledgerKind(_ kind: String) -> String {
    switch kind {
    case "anchor": "Anchor"
    case "topup": "Top-up"
    case "reconcile": "Reconcile"
    case "note": "Note"
    default: "Auto-zero"
    }
  }

  // Set anchor and Add top-up sheets (08)
  static let amount = "Amount"
  static let asOf = "As of"
  static let date = "Date"
  static let note = "Note"
  static let anchorHelp = "Enter the balance shown on the provider\u{2019}s billing page right now."
  static let cancel = "Cancel"
  static let setAnchorButton = "Set anchor"
  static let addTopUpButton = "Add top-up"
  static let ledgerSaveFailed = "TokenBe could not save this entry. Try again."

  // Settings → Alerts (08 § Settings, 09 § Alerts)
  static let tabAlerts = "Alerts"
  static let thresholds = "Thresholds"
  static let watchDays = "Watch below"
  static let lowDays = "Low below"
  static let criticalDays = "Critical below"
  static let dollarFloor = "Critical below amount"
  static let staleMultiplier = "Stale after"
  static let driftThreshold = "Flag drift above"
  static let anchorAge = "Anchor age nudge after"
  static func intervals(_ value: Int) -> String { "\(value) \u{00D7} interval" }
  static func percent(_ value: Int) -> String { "\(value) %" }

  // Settings → Accounts: auto-reload (09 `account.auto_reload_*`, 05)
  static let autoReload = "Auto-reload"
  static let autoReloadBelow = "Reloads below"
  static let autoReloadTo = "Adds"

  // Settings → Alerts: notifications (08 § Settings, 09 § Alerts, O-11; 14 § Stage 5.4)
  static let notifications = "Notifications"
  static let notifyLow = "Notify when an account turns low"
  static let notifyCritical = "Notify when an account turns critical"
  static let notifyUnknown = "Notify when an anchor is missing for a day"
  static let notifyStale = "Notify when data is stale for 6 h"
  static let quietHours = "Quiet hours"
  static let quietFrom = "From"
  static let quietUntil = "Until"
  static let sendTestNotification = "Send test notification"
  static let testSent = "Sent"
  static let testNotSent = "Not sent: notifications are off"
  static let notificationsOff = "Notifications are off in System Settings"
  static let openSystemSettings = "Open System Settings"
  static let notificationSettingsURL = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

  // Apps (14 § Stage 7.1): the account page's By-app table (08 § Account detail 4), Overview `Apps this period`
  // (§ Overview 4), popover row 4 (§ Popover 3), the sidebar's `Apps` and Keys & apps (§ Settings). Copy 08 does not
  // give is authored (Q-048).
  static let apps = "Apps"
  static let byApp = "By app"
  static let appsThisPeriod = "Apps this period"
  static let columnApp = "App"
  static let columnKey = "Key"
  static let columnRequests = "Requests"
  static let columnTokens = "Tokens"
  static let columnSpend = "Spend"
  static let columnShare = "Share"
  static let total = "Total"
  static let nameKey = "Name\u{2026}"
  static let boundApp = "Bound app"
  static let newApp = "New app\u{2026}"
  static let noApp = "\u{2014}"
  static let appNameField = "App name"
  static let create = "Create"
  static let appTag = "Harness tag"
  static let noAppsYet = "No apps yet"
  static let noAppsBody = "Name a key in an account\u{2019}s By app table, or bind it in Settings \u{2192} Accounts \u{2192} Keys & apps."
  static let showApps = "Show apps"
  static let hideApps = "Hide apps"
  /// Popover row 4 (08): with more than three apps, the rest in one entry.
  static let otherApps = "other"
  /// 08: an unbound provider key, `(unnamed key …a9f2)`.
  static func unnamedKeyHint(_ hint: String) -> String { "(unnamed key \(hint))" }
  /// `weather-collector $1.20` (08 popover row 4).
  static func appEntry(_ name: String, _ amount: String) -> String { "\(name) \(amount)" }
  /// The badge of each attribution kind (08: `key` / `≈ split` / `harness` / `inferred`; 7.1 has only `key`).
  static func badge(_ kind: AttributionKind) -> String {
    switch kind {
    case .key: "key"
    case .split: "\u{2248} split"
    case .harness: "harness"
    case .inferred: "inferred"
    }
  }

  // Harness reports (08 § Settings → Sources, `21S-0`; 14 § Stage 7.2). Authored copy is logged in Q-049.
  static let harnessReports = "Harness reports"
  static let harnessFolder = "Folder"
  static let revealInFinder = "Reveal in Finder"
  static let harnessWatch = "Watch the folder"
  static let harnessMoveWhenDone = "Move files to ingested/ when done"
  static let harnessOff = "Off"
  static let harnessUnwritable = "The folder is not writable. Harness reports are off."
  static let copyReporterSnippet = "Copy reporter snippet"
  static let snippetPython = "Python"
  static let snippetNode = "Node"
  static func snippetCopied(_ language: String) -> String { "\(language) snippet copied" }
  static func secondsAgo(_ seconds: Int) -> String { "\(seconds) s ago" }
  /// 08: `Watching · 2 files · last line 14 s ago`.
  static func harnessWatching(files: Int, lastLine: String?) -> String {
    "Watching \u{00B7} \(files) \(files == 1 ? "file" : "files") \u{00B7} " + (lastLine.map { "last line \($0)" } ?? "no lines yet")
  }
  static func harnessToday(inserted: Int, duplicate: Int, rejected: Int) -> String {
    "Today: \(inserted) ok \u{00B7} \(duplicate) duplicate \u{00B7} \(rejected) rejected"
  }
  /// O-12.
  static func harnessWithoutAccount(_ lines: Int) -> String {
    "\(lines) \(lines == 1 ? "line" : "lines") for providers you haven\u{2019}t added"
  }
  static func harnessRotate(_ file: String) -> String { "\(file) is over 512 MiB. Start a new file to rotate it." }
  /// 08: the empty By-app table, which opens Settings → Sources.
  static let reportAppsFromHarness = "Report apps from your harness \u{2192}"
  /// 08 Sources strip: `Harness · 3 files · 12 lines today` (the title, then this line).
  static let sourceHarness = "Harness"
  static func harnessLine(files: Int, linesToday: Int) -> String {
    "\(files) \(files == 1 ? "file" : "files") \u{00B7} \(linesToday) lines today"
  }

  // 7.3 drilldown: 08 gives no copy for the app filter or the drift chip (Q-050).
  /// The account page's filter chip, `App: news-digest`, and its ✕.
  static func appFilter(_ name: String) -> String { "App: \(name)" }
  static let clearAppFilter = "Clear app filter"
  /// The filtered By-app table's `Total` row, and the table with no row of the app in the range.
  static let appTotal = "App total"
  static func noAppSpend(_ name: String) -> String { "No spend for \(name) in this range" }
  /// 06's drift chip: `Harness drift · Nov 14 · −$4.02`, then ` · 3 days` when more closed days drifted.
  static func harnessDrift(day: String, amount: String, days: Int) -> String {
    "Harness drift \u{00B7} \(day) \u{00B7} \(amount)" + (days > 1 ? " \u{00B7} \(days) days" : "")
  }
  static func harnessDriftHelp(day: String, harness: String, balance: String) -> String {
    "On \(day) harness lines add up to \(harness), but the balance fell by \(balance). Lines may be missing, or a "
      + "request was reported under another provider."
  }

  // 8.1 By-model table (08 § Account detail 5, `G7-0`): the column titles are 08's; the rest is authored (Q-051).
  static let byModel = "By model"
  static let columnModel = "Model"
  static let columnInput = "Input"
  static let columnCacheWrite = "Cache write"
  static let columnCacheRead = "Cache read"
  static let columnOutput = "Output"
  static let columnReasoning = "Reasoning"
  static let columnEstCost = "Est. cost"
  static let columnProviderCost = "Provider cost"
  static let columnDrift = "Drift"
  /// The Est. cost cell of a model the price book cannot price (A6), in `HealthWatch`.
  static let unpricedModel = "unpriced"
  static let unpricedModelHelp = "This model is not in the price book, so its usage is left out of spend and "
    + "runway. Add a price in Settings \u{2192} Sources \u{2192} Price book."
  /// Provider cost or Drift without a provider cost row for the model (05).
  static let noProviderCost = "\u{2014}"
  static let noProviderCostHelp = "The provider reports no cost for this model in this range."
  /// The Drift cell's help: the two figures over exactly the days drift compares (05 § Drift, Q-051).
  static func driftHelp(days: Int, estimate: String, provider: String) -> String {
    "Over \(days) closed \(days == 1 ? "day" : "days") with a provider cost: estimate \(estimate), provider \(provider)."
  }
  /// The Drift cell's VoiceOver label; flagged cells say so in words, not only in colour (08 § Accessibility).
  static func driftLabel(_ percent: String, flagged: Bool, thresholdPct: Int) -> String {
    flagged ? "Drift \(percent), above the \(thresholdPct) % threshold" : "Drift \(percent)"
  }

  /// The name a By-app row shows: the bound app's display name (O-13), else the provider's key name (01 A2: human
  /// key names), else 08's `(unnamed key …a9f2)` (Q-048).
  static func appLabel(_ row: AppRow) -> String {
    row.appName ?? row.keyName ?? unnamedKeyHint(row.keyHint.map(hint) ?? noApp)
  }
}

/// 14 § Stage 8.2: the Overview's `Spend by day` chart and cache savings tile (an extension keeps `Strings` under
/// the type-length limit).
extension Strings {
  /// The chart's VoiceOver label (08 § Overview 3, 14 § Stage 8.2).
  static let spendByDayChart = "Spend by day, stacked by account"
  /// The tooltip's last row.
  static let chartTotal = "Total"
  /// The hovered day's rule for VoiceOver: `Total, Nov 14, ≈ $3.20` (a chart mark's value is not exposed).
  static func chartTotalOn(_ day: String, amount: String) -> String { "\(chartTotal), \(day), \(amount)" }
  /// The chart's caption when accounts in another currency have spend (05 § Currency: nothing is converted; Q-052).
  static func chartNonUSD(_ count: Int) -> String {
    "USD accounts only \u{00B7} \(count) non-USD account\(count == 1 ? "" : "s") not shown"
  }
  /// A bar segment's VoiceOver label: `OpenAI, Nov 14`.
  static func chartSegment(account: String, day: String) -> String { "\(account), \(day)" }
  /// The chart's per-day totals for VoiceOver (PM-8.2-2): `Nov 17, total approximately 0.64 dollars`.
  static func chartDayTotal(_ day: String, amount: String) -> String { "\(day), total \(amount)" }
  static let spendByDayTotals = "Spend by day, totals"

  // Overview cache savings tile (08 § Overview 5, 05 § Cache savings; 14 § Stage 8.2)
  static let cacheSavings = "Cache savings"
  /// `Saved $12 via cache (net of writes)`.
  static func cacheSaved(_ amount: String) -> String { "Saved \(amount) via cache (net of writes)" }
  static let cacheNotComputed = "Not computed for any account in this range"
  static let cacheGap = "\u{2014}"
  static let cacheSavedHelp = "Cached tokens priced as plain input, minus what the cache reads and writes cost, at "
    + "price-book rates, in dollars."
  /// Why an account's savings read `—` (05).
  static func cacheGapHelp(_ gap: CacheSavingsGap?) -> String {
    switch gap {
    case .openAIAggregate: "Not computed \u{2014} OpenAI aggregate cache counts are unreliable"
    case .noCacheCounts: "Not computed \u{2014} this provider reports no cache token counts"
    case .noHarnessReports: "Computed from harness reports; none in this range"
    case .noUsage: "No usage in this range"
    case nil: noDataYet
    }
  }

  // Toolbar `Export…` (08 § Dashboard window; O-4; 14 § Stage 8.3)
  static let exportEllipsis = "Export\u{2026}"
  static let exportHelp = "Save the table on this page as a CSV file"
  /// The By-app badge column's CSV header (untitled on screen).
  static let columnAttribution = "Attribution"
  static let byAppFile = "By app"
  static let exportFailed = "The CSV file could not be saved."
}

/// Stage 8.4's VoiceOver copy (08 § Accessibility): each figure is read as its title and its words, never the
/// screen's symbols (`≈`, `±`, `~12 d`, `CN¥`). The words themselves come from Core's `Spoken`.
extension Strings {
  /// `Remaining, approximately 42 dollars, plus or minus 3` (08).
  static func spoken(_ title: String, _ value: String) -> String { "\(title), \(value)" }
  static let spoken30d = "Spend 30 days"
  static func spokenPerDay(_ amount: String) -> String { "\(amount) per day" }
  static func spokenShortestRunway(_ label: String, _ runway: String, band: String) -> String {
    "Shortest runway: \(label), \(runway), band \(band)"
  }
  static func spokenTotalRemaining(_ amount: String, usdAccounts: Int, nonUSD: Int) -> String {
    "Total remaining, \(amount), across \(usdAccounts) USD account\(usdAccounts == 1 ? "" : "s")"
      + (nonUSD > 0 ? ", plus \(nonUSD) non-USD" : "")
  }
  static func spokenBanner(_ line: String, band: String) -> String { "\(line), band \(band)" }
  static func spokenDays(_ days: Int) -> String { "\(days) days" }
  static func spokenTotalSpend(range: String, amount: String, nonUSD: Int) -> String {
    "Total spend \(range), \(amount)" + (nonUSD > 0 ? ", plus \(nonUSD) non-USD" : "")
  }
  /// A spinner's VoiceOver label under Reduce Motion, where it is a pulsing dot.
  static let busy = "In progress"
}
