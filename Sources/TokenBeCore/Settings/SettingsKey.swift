// Generated from docs/09-settings-spec.md — the 09 tables ARE the registration list (09 intro, 14 § Stage 0.3).
// `scripts/stages/0.3.sh` fails when this file and 09 list different keys.

/// Every stored setting of 09 except the per-provider templated keys (`TemplatedSettingsKey`).
public enum SettingsKey: String, CaseIterable, Sendable {
  case generalLaunchAtLogin = "tb.general.launchAtLogin"
  case menubarGlyphStyle = "tb.menubar.glyphStyle"
  case menubarMetric = "tb.menubar.metric"
  case popoverPinnedMetric = "tb.popover.pinnedMetric"
  case popoverSort = "tb.popover.sort"
  case popoverManualOrder = "tb.popover.manualOrder"
  case uiCurrencyDisplay = "tb.ui.currencyDisplay"
  case uiHideCents = "tb.ui.hideCents"
  case uiAppearance = "tb.ui.appearance"
  case uiUseSystemAccent = "tb.ui.useSystemAccent"
  case uiShortcut = "tb.ui.shortcut"
  case uiDashboardFrame = "tb.ui.dashboardFrame"
  case uiDashboardRange = "tb.ui.dashboardRange"
  case uiOnboardingDone = "tb.ui.onboardingDone"
  case pollBalanceIntervalS = "tb.poll.balanceIntervalS"
  case pollUsageIntervalAnthropicS = "tb.poll.usageIntervalAnthropicS"
  case pollUsageIntervalOpenAIS = "tb.poll.usageIntervalOpenAIS"
  case pollKeysIntervalS = "tb.poll.keysIntervalS"
  case dailyLastRunAt = "tb.daily.lastRunAt"
  case dailyRunCount = "tb.daily.runCount"
  case pollLowPowerMultiplier = "tb.poll.lowPowerMultiplier"
  case pollPausedUntil = "tb.poll.pausedUntil"
  case ingestEnabled = "tb.ingest.enabled"
  case ingestMoveWhenDone = "tb.ingest.moveWhenDone"
  case ingestFolderPath = "tb.ingest.folderPath"
  case priceFeedEnabled = "tb.price.feedEnabled"
  case priceFeedURL = "tb.price.feedURL"
  case priceStaleAfterDays = "tb.price.staleAfterDays"
  case alertsWatchDays = "tb.alerts.watchDays"
  case alertsLowDays = "tb.alerts.lowDays"
  case alertsCriticalDays = "tb.alerts.criticalDays"
  case alertsDollarFloorCents = "tb.alerts.dollarFloorCents"
  case alertsStaleMultiplier = "tb.alerts.staleMultiplier"
  case alertsDriftThresholdPct = "tb.alerts.driftThresholdPct"
  case alertsAnchorAgeDays = "tb.alerts.anchorAgeDays"
  case alertsNotifyLow = "tb.alerts.notify.low"
  case alertsNotifyCritical = "tb.alerts.notify.critical"
  case alertsNotifyUnknown = "tb.alerts.notify.unknown"
  case alertsNotifyStale = "tb.alerts.notify.stale"
  case alertsQuietHoursEnabled = "tb.alerts.quietHoursEnabled"
  case alertsQuietStart = "tb.alerts.quietStart"
  case alertsQuietEnd = "tb.alerts.quietEnd"
  case updateCheckEnabled = "tb.update.checkEnabled"
  case updateLastCheckedAt = "tb.update.lastCheckedAt"
  case updateLatestSeen = "tb.update.latestSeen"
  case updateIgnoredVersion = "tb.update.ignoredVersion"
  case logLevel = "tb.log.level"
  case logRetentionDays = "tb.log.retentionDays"
  case retentionHourlyDays = "tb.retention.hourlyDays"
  case retentionRawHarnessDays = "tb.retention.rawHarnessDays"
  case dbLastBackupAt = "tb.db.lastBackupAt"
  case dbLastIntegrityCheckAt = "tb.db.lastIntegrityCheckAt"
  case debugFixtureMode = "tb.debug.fixtureMode"

  /// Type, default, allowed values and tab, straight from 09.
  public var spec: SettingSpec {
    switch self {
    case .generalLaunchAtLogin: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .general)
    case .menubarGlyphStyle: SettingSpec(type: .string, defaultValue: .string("ring"), rule: .oneOf(["ring"]), tab: .general)
    case .menubarMetric: SettingSpec(type: .string, defaultValue: .string("minRunway"), rule: .oneOf(["none", "minRunway", "minRemaining", "todaySpend"]), tab: .general)
    case .popoverPinnedMetric: SettingSpec(type: .string, defaultValue: .string("runway"), rule: .oneOf(["runway", "remaining", "todaySpend"]), tab: .general)
    case .popoverSort: SettingSpec(type: .string, defaultValue: .string("runway"), rule: .oneOf(["runway", "remaining", "name", "manual"]), tab: .general)
    case .popoverManualOrder: SettingSpec(type: .strings, defaultValue: .strings([]), rule: .providerIDs, tab: .general)
    case .uiCurrencyDisplay: SettingSpec(type: .string, defaultValue: .string("native"), rule: .oneOf(["native"]), tab: .general)
    case .uiHideCents: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .general)
    case .uiAppearance: SettingSpec(type: .string, defaultValue: .string("system"), rule: .oneOf(["system", "light", "dark"]), tab: .general)
    case .uiUseSystemAccent: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .general)
    case .uiShortcut: SettingSpec(type: .string, defaultValue: .string("ctrl+alt+t"), rule: .pattern(.shortcut), tab: .general)
    case .uiDashboardFrame: SettingSpec(type: .string, defaultValue: .string(""), rule: .pattern(.rect), tab: .general)
    case .uiDashboardRange: SettingSpec(type: .string, defaultValue: .string("7d"), rule: .oneOf(["today", "7d", "30d", "90d"]), tab: .general)
    case .uiOnboardingDone: SettingSpec(type: .bool, defaultValue: .bool(false), rule: .none, tab: .general)
    case .pollBalanceIntervalS: SettingSpec(type: .int, defaultValue: .int(60), rule: .intRange(30...3600), tab: .sources)
    case .pollUsageIntervalAnthropicS: SettingSpec(type: .int, defaultValue: .int(60), rule: .intRange(60...3600), tab: .sources)
    case .pollUsageIntervalOpenAIS: SettingSpec(type: .int, defaultValue: .int(300), rule: .intRange(60...3600), tab: .sources)
    case .pollKeysIntervalS: SettingSpec(type: .int, defaultValue: .int(3600), rule: .intRange(600...86400), tab: .sources)
    case .dailyLastRunAt: SettingSpec(type: .double, defaultValue: .double(0), rule: .doubleMin(0), tab: .sources)
    case .dailyRunCount: SettingSpec(type: .int, defaultValue: .int(0), rule: .intRange(0...Int.max), tab: .sources)
    case .pollLowPowerMultiplier: SettingSpec(type: .int, defaultValue: .int(4), rule: .intRange(1...10), tab: .sources)
    case .pollPausedUntil: SettingSpec(type: .double, defaultValue: .double(0), rule: .doubleMin(0), tab: .sources)
    case .ingestEnabled: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .sources)
    case .ingestMoveWhenDone: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .sources)
    case .ingestFolderPath: SettingSpec(type: .string, defaultValue: .string(SettingSpec.ingestFolderPath), rule: .fixed, tab: .sources)
    case .priceFeedEnabled: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .sources)
    case .priceFeedURL: SettingSpec(type: .string, defaultValue: .string("https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"), rule: .pattern(.httpsURL), tab: .advanced)
    case .priceStaleAfterDays: SettingSpec(type: .int, defaultValue: .int(7), rule: .intRange(1...60), tab: .sources)
    case .alertsWatchDays: SettingSpec(type: .int, defaultValue: .int(14), rule: .threshold(2...365), tab: .alerts)
    case .alertsLowDays: SettingSpec(type: .int, defaultValue: .int(7), rule: .threshold(1...364), tab: .alerts)
    case .alertsCriticalDays: SettingSpec(type: .int, defaultValue: .int(2), rule: .threshold(0...363), tab: .alerts)
    case .alertsDollarFloorCents: SettingSpec(type: .int, defaultValue: .int(500), rule: .intRange(0...100000), tab: .alerts)
    case .alertsStaleMultiplier: SettingSpec(type: .int, defaultValue: .int(3), rule: .intRange(2...10), tab: .alerts)
    case .alertsDriftThresholdPct: SettingSpec(type: .int, defaultValue: .int(10), rule: .intRange(1...100), tab: .alerts)
    case .alertsAnchorAgeDays: SettingSpec(type: .int, defaultValue: .int(30), rule: .intRange(7...365), tab: .alerts)
    case .alertsNotifyLow: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .alerts)
    case .alertsNotifyCritical: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .alerts)
    case .alertsNotifyUnknown: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .alerts)
    case .alertsNotifyStale: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .alerts)
    case .alertsQuietHoursEnabled: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .alerts)
    case .alertsQuietStart: SettingSpec(type: .string, defaultValue: .string("23:00"), rule: .pattern(.clockTime), tab: .alerts)
    case .alertsQuietEnd: SettingSpec(type: .string, defaultValue: .string("07:00"), rule: .pattern(.clockTime), tab: .alerts)
    case .updateCheckEnabled: SettingSpec(type: .bool, defaultValue: .bool(true), rule: .none, tab: .privacy)
    case .updateLastCheckedAt: SettingSpec(type: .double, defaultValue: .double(0), rule: .doubleMin(0), tab: .privacy)
    case .updateLatestSeen: SettingSpec(type: .string, defaultValue: .string(""), rule: .pattern(.semver), tab: .privacy)
    case .updateIgnoredVersion: SettingSpec(type: .string, defaultValue: .string(""), rule: .pattern(.semver), tab: .privacy)
    case .logLevel: SettingSpec(type: .string, defaultValue: .string("info"), rule: .oneOf(["debug", "info", "warn", "error"]), tab: .advanced)
    case .logRetentionDays: SettingSpec(type: .int, defaultValue: .int(14), rule: .intRange(1...90), tab: .advanced)
    case .retentionHourlyDays: SettingSpec(type: .int, defaultValue: .int(90), rule: .intRange(30...730), tab: .advanced)
    case .retentionRawHarnessDays: SettingSpec(type: .int, defaultValue: .int(90), rule: .intRange(7...730), tab: .advanced)
    case .dbLastBackupAt: SettingSpec(type: .double, defaultValue: .double(0), rule: .doubleMin(0), tab: .advanced)
    case .dbLastIntegrityCheckAt: SettingSpec(type: .double, defaultValue: .double(0), rule: .doubleMin(0), tab: .advanced)
    case .debugFixtureMode: SettingSpec(type: .bool, defaultValue: .bool(false), rule: .none, tab: .advanced)
    }
  }
}
