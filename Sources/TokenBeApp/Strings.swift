/// Every user-visible string (12 § R9, 08), exactly as 08 writes it. Views never contain inline copy.
enum Strings {
  static let appName = "TokenBe"

  // Popover — Empty state (08 § Popover states)
  static let emptyHeadline = "No accounts yet"
  static let emptyBody = "Add a provider key to start tracking."

  // Popover — cards (08 § Popover, § Popover states)
  static let noDataYet = "No data yet"
  static let modeAnchored = "\u{2248}"
  static let modeSpendOnly = "spend"

  // Popover — footer (08 § Popover 4)
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
}
