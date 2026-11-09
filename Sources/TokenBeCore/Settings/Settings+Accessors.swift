// Generated from docs/09-settings-spec.md: one typed property per `SettingsKey` (14 § Stage 0.3 step 3).

extension Settings {
  public var generalLaunchAtLogin: Bool {
    get { bool(.generalLaunchAtLogin) }
    set { set(.generalLaunchAtLogin, .bool(newValue)) }
  }

  public var menubarGlyphStyle: String {
    get { string(.menubarGlyphStyle) }
    set { set(.menubarGlyphStyle, .string(newValue)) }
  }

  public var menubarMetric: String {
    get { string(.menubarMetric) }
    set { set(.menubarMetric, .string(newValue)) }
  }

  public var popoverPinnedMetric: String {
    get { string(.popoverPinnedMetric) }
    set { set(.popoverPinnedMetric, .string(newValue)) }
  }

  public var popoverSort: String {
    get { string(.popoverSort) }
    set { set(.popoverSort, .string(newValue)) }
  }

  public var popoverManualOrder: [String] {
    get { strings(.popoverManualOrder) }
    set { set(.popoverManualOrder, .strings(newValue)) }
  }

  public var uiCurrencyDisplay: String {
    get { string(.uiCurrencyDisplay) }
    set { set(.uiCurrencyDisplay, .string(newValue)) }
  }

  public var uiHideCents: Bool {
    get { bool(.uiHideCents) }
    set { set(.uiHideCents, .bool(newValue)) }
  }

  public var uiAppearance: String {
    get { string(.uiAppearance) }
    set { set(.uiAppearance, .string(newValue)) }
  }

  public var uiUseSystemAccent: Bool {
    get { bool(.uiUseSystemAccent) }
    set { set(.uiUseSystemAccent, .bool(newValue)) }
  }

  public var uiShortcut: String {
    get { string(.uiShortcut) }
    set { set(.uiShortcut, .string(newValue)) }
  }

  public var uiDashboardFrame: String {
    get { string(.uiDashboardFrame) }
    set { set(.uiDashboardFrame, .string(newValue)) }
  }

  public var uiDashboardRange: String {
    get { string(.uiDashboardRange) }
    set { set(.uiDashboardRange, .string(newValue)) }
  }

  public var uiOnboardingDone: Bool {
    get { bool(.uiOnboardingDone) }
    set { set(.uiOnboardingDone, .bool(newValue)) }
  }

  public var pollBalanceIntervalS: Int {
    get { int(.pollBalanceIntervalS) }
    set { set(.pollBalanceIntervalS, .int(newValue)) }
  }

  public var pollUsageIntervalAnthropicS: Int {
    get { int(.pollUsageIntervalAnthropicS) }
    set { set(.pollUsageIntervalAnthropicS, .int(newValue)) }
  }

  public var pollUsageIntervalOpenAIS: Int {
    get { int(.pollUsageIntervalOpenAIS) }
    set { set(.pollUsageIntervalOpenAIS, .int(newValue)) }
  }

  public var pollKeysIntervalS: Int {
    get { int(.pollKeysIntervalS) }
    set { set(.pollKeysIntervalS, .int(newValue)) }
  }

  public var dailyLastRunAt: Double {
    get { double(.dailyLastRunAt) }
    set { set(.dailyLastRunAt, .double(newValue)) }
  }

  public var dailyRunCount: Int {
    get { int(.dailyRunCount) }
    set { set(.dailyRunCount, .int(newValue)) }
  }

  public var pollLowPowerMultiplier: Int {
    get { int(.pollLowPowerMultiplier) }
    set { set(.pollLowPowerMultiplier, .int(newValue)) }
  }

  public var pollPausedUntil: Double {
    get { double(.pollPausedUntil) }
    set { set(.pollPausedUntil, .double(newValue)) }
  }

  public var ingestEnabled: Bool {
    get { bool(.ingestEnabled) }
    set { set(.ingestEnabled, .bool(newValue)) }
  }

  public var ingestMoveWhenDone: Bool {
    get { bool(.ingestMoveWhenDone) }
    set { set(.ingestMoveWhenDone, .bool(newValue)) }
  }

  public var ingestFolderPath: String {
    get { string(.ingestFolderPath) }
    set { set(.ingestFolderPath, .string(newValue)) }
  }

  public var priceFeedEnabled: Bool {
    get { bool(.priceFeedEnabled) }
    set { set(.priceFeedEnabled, .bool(newValue)) }
  }

  public var priceFeedURL: String {
    get { string(.priceFeedURL) }
    set { set(.priceFeedURL, .string(newValue)) }
  }

  public var priceStaleAfterDays: Int {
    get { int(.priceStaleAfterDays) }
    set { set(.priceStaleAfterDays, .int(newValue)) }
  }

  public var alertsWatchDays: Int {
    get { int(.alertsWatchDays) }
    set { set(.alertsWatchDays, .int(newValue)) }
  }

  public var alertsLowDays: Int {
    get { int(.alertsLowDays) }
    set { set(.alertsLowDays, .int(newValue)) }
  }

  public var alertsCriticalDays: Int {
    get { int(.alertsCriticalDays) }
    set { set(.alertsCriticalDays, .int(newValue)) }
  }

  public var alertsDollarFloorCents: Int {
    get { int(.alertsDollarFloorCents) }
    set { set(.alertsDollarFloorCents, .int(newValue)) }
  }

  public var alertsStaleMultiplier: Int {
    get { int(.alertsStaleMultiplier) }
    set { set(.alertsStaleMultiplier, .int(newValue)) }
  }

  public var alertsDriftThresholdPct: Int {
    get { int(.alertsDriftThresholdPct) }
    set { set(.alertsDriftThresholdPct, .int(newValue)) }
  }

  public var alertsAnchorAgeDays: Int {
    get { int(.alertsAnchorAgeDays) }
    set { set(.alertsAnchorAgeDays, .int(newValue)) }
  }

  public var alertsNotifyLow: Bool {
    get { bool(.alertsNotifyLow) }
    set { set(.alertsNotifyLow, .bool(newValue)) }
  }

  public var alertsNotifyCritical: Bool {
    get { bool(.alertsNotifyCritical) }
    set { set(.alertsNotifyCritical, .bool(newValue)) }
  }

  public var alertsNotifyUnknown: Bool {
    get { bool(.alertsNotifyUnknown) }
    set { set(.alertsNotifyUnknown, .bool(newValue)) }
  }

  public var alertsNotifyStale: Bool {
    get { bool(.alertsNotifyStale) }
    set { set(.alertsNotifyStale, .bool(newValue)) }
  }

  public var alertsQuietHoursEnabled: Bool {
    get { bool(.alertsQuietHoursEnabled) }
    set { set(.alertsQuietHoursEnabled, .bool(newValue)) }
  }

  public var alertsQuietStart: String {
    get { string(.alertsQuietStart) }
    set { set(.alertsQuietStart, .string(newValue)) }
  }

  public var alertsQuietEnd: String {
    get { string(.alertsQuietEnd) }
    set { set(.alertsQuietEnd, .string(newValue)) }
  }

  public var updateCheckEnabled: Bool {
    get { bool(.updateCheckEnabled) }
    set { set(.updateCheckEnabled, .bool(newValue)) }
  }

  public var updateLastCheckedAt: Double {
    get { double(.updateLastCheckedAt) }
    set { set(.updateLastCheckedAt, .double(newValue)) }
  }

  public var updateLatestSeen: String {
    get { string(.updateLatestSeen) }
    set { set(.updateLatestSeen, .string(newValue)) }
  }

  public var updateIgnoredVersion: String {
    get { string(.updateIgnoredVersion) }
    set { set(.updateIgnoredVersion, .string(newValue)) }
  }

  public var logLevel: String {
    get { string(.logLevel) }
    set { set(.logLevel, .string(newValue)) }
  }

  public var logRetentionDays: Int {
    get { int(.logRetentionDays) }
    set { set(.logRetentionDays, .int(newValue)) }
  }

  public var retentionHourlyDays: Int {
    get { int(.retentionHourlyDays) }
    set { set(.retentionHourlyDays, .int(newValue)) }
  }

  public var retentionRawHarnessDays: Int {
    get { int(.retentionRawHarnessDays) }
    set { set(.retentionRawHarnessDays, .int(newValue)) }
  }

  public var dbLastBackupAt: Double {
    get { double(.dbLastBackupAt) }
    set { set(.dbLastBackupAt, .double(newValue)) }
  }

  public var dbLastIntegrityCheckAt: Double {
    get { double(.dbLastIntegrityCheckAt) }
    set { set(.dbLastIntegrityCheckAt, .double(newValue)) }
  }

  public var debugFixtureMode: Bool {
    get { bool(.debugFixtureMode) }
    set { set(.debugFixtureMode, .bool(newValue)) }
  }
}
