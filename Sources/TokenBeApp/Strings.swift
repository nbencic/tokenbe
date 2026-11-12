import Foundation
import TokenBeCore

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
  static let cancel = "Cancel"
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
}
