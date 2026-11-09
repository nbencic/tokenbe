// Generated alongside Settings+Accessors.swift: every typed property reads its 09 default and writes back.
import Testing
@testable import TokenBeCore

@MainActor @Suite struct SettingsAccessorTests {
  static func makeSettings() -> Settings {
    Settings(store: InMemorySettingsStore(), logPipeline: LogPipeline(sinks: [], version: "test"))
  }

  @Test("typed accessors, part 1: each returns its 09 default and accepts a write")
  func accessorsPart1() {
    let settings = Self.makeSettings()
    settings.generalLaunchAtLogin = settings.generalLaunchAtLogin
    #expect(settings.value(.generalLaunchAtLogin) == SettingsKey.generalLaunchAtLogin.spec.defaultValue)
    settings.menubarGlyphStyle = settings.menubarGlyphStyle
    #expect(settings.value(.menubarGlyphStyle) == SettingsKey.menubarGlyphStyle.spec.defaultValue)
    settings.menubarMetric = settings.menubarMetric
    #expect(settings.value(.menubarMetric) == SettingsKey.menubarMetric.spec.defaultValue)
    settings.popoverPinnedMetric = settings.popoverPinnedMetric
    #expect(settings.value(.popoverPinnedMetric) == SettingsKey.popoverPinnedMetric.spec.defaultValue)
    settings.popoverSort = settings.popoverSort
    #expect(settings.value(.popoverSort) == SettingsKey.popoverSort.spec.defaultValue)
    settings.popoverManualOrder = settings.popoverManualOrder
    #expect(settings.value(.popoverManualOrder) == SettingsKey.popoverManualOrder.spec.defaultValue)
    settings.uiCurrencyDisplay = settings.uiCurrencyDisplay
    #expect(settings.value(.uiCurrencyDisplay) == SettingsKey.uiCurrencyDisplay.spec.defaultValue)
    settings.uiHideCents = settings.uiHideCents
    #expect(settings.value(.uiHideCents) == SettingsKey.uiHideCents.spec.defaultValue)
    settings.uiAppearance = settings.uiAppearance
    #expect(settings.value(.uiAppearance) == SettingsKey.uiAppearance.spec.defaultValue)
    settings.uiUseSystemAccent = settings.uiUseSystemAccent
    #expect(settings.value(.uiUseSystemAccent) == SettingsKey.uiUseSystemAccent.spec.defaultValue)
    settings.uiShortcut = settings.uiShortcut
    #expect(settings.value(.uiShortcut) == SettingsKey.uiShortcut.spec.defaultValue)
    settings.uiDashboardFrame = settings.uiDashboardFrame
    #expect(settings.value(.uiDashboardFrame) == SettingsKey.uiDashboardFrame.spec.defaultValue)
    settings.uiDashboardRange = settings.uiDashboardRange
    #expect(settings.value(.uiDashboardRange) == SettingsKey.uiDashboardRange.spec.defaultValue)
    settings.uiOnboardingDone = settings.uiOnboardingDone
    #expect(settings.value(.uiOnboardingDone) == SettingsKey.uiOnboardingDone.spec.defaultValue)
    settings.pollBalanceIntervalS = settings.pollBalanceIntervalS
    #expect(settings.value(.pollBalanceIntervalS) == SettingsKey.pollBalanceIntervalS.spec.defaultValue)
    settings.pollUsageIntervalAnthropicS = settings.pollUsageIntervalAnthropicS
    #expect(settings.value(.pollUsageIntervalAnthropicS) == SettingsKey.pollUsageIntervalAnthropicS.spec.defaultValue)
    settings.pollUsageIntervalOpenAIS = settings.pollUsageIntervalOpenAIS
    #expect(settings.value(.pollUsageIntervalOpenAIS) == SettingsKey.pollUsageIntervalOpenAIS.spec.defaultValue)
    settings.pollKeysIntervalS = settings.pollKeysIntervalS
    #expect(settings.value(.pollKeysIntervalS) == SettingsKey.pollKeysIntervalS.spec.defaultValue)
    settings.dailyLastRunAt = settings.dailyLastRunAt
    #expect(settings.value(.dailyLastRunAt) == SettingsKey.dailyLastRunAt.spec.defaultValue)
    settings.dailyRunCount = settings.dailyRunCount
    #expect(settings.value(.dailyRunCount) == SettingsKey.dailyRunCount.spec.defaultValue)
  }

  @Test("typed accessors, part 2: each returns its 09 default and accepts a write")
  func accessorsPart2() {
    let settings = Self.makeSettings()
    settings.pollLowPowerMultiplier = settings.pollLowPowerMultiplier
    #expect(settings.value(.pollLowPowerMultiplier) == SettingsKey.pollLowPowerMultiplier.spec.defaultValue)
    settings.pollPausedUntil = settings.pollPausedUntil
    #expect(settings.value(.pollPausedUntil) == SettingsKey.pollPausedUntil.spec.defaultValue)
    settings.ingestEnabled = settings.ingestEnabled
    #expect(settings.value(.ingestEnabled) == SettingsKey.ingestEnabled.spec.defaultValue)
    settings.ingestMoveWhenDone = settings.ingestMoveWhenDone
    #expect(settings.value(.ingestMoveWhenDone) == SettingsKey.ingestMoveWhenDone.spec.defaultValue)
    settings.ingestFolderPath = settings.ingestFolderPath
    #expect(settings.value(.ingestFolderPath) == SettingsKey.ingestFolderPath.spec.defaultValue)
    settings.priceFeedEnabled = settings.priceFeedEnabled
    #expect(settings.value(.priceFeedEnabled) == SettingsKey.priceFeedEnabled.spec.defaultValue)
    settings.priceFeedURL = settings.priceFeedURL
    #expect(settings.value(.priceFeedURL) == SettingsKey.priceFeedURL.spec.defaultValue)
    settings.priceStaleAfterDays = settings.priceStaleAfterDays
    #expect(settings.value(.priceStaleAfterDays) == SettingsKey.priceStaleAfterDays.spec.defaultValue)
    settings.alertsWatchDays = settings.alertsWatchDays
    #expect(settings.value(.alertsWatchDays) == SettingsKey.alertsWatchDays.spec.defaultValue)
    settings.alertsLowDays = settings.alertsLowDays
    #expect(settings.value(.alertsLowDays) == SettingsKey.alertsLowDays.spec.defaultValue)
    settings.alertsCriticalDays = settings.alertsCriticalDays
    #expect(settings.value(.alertsCriticalDays) == SettingsKey.alertsCriticalDays.spec.defaultValue)
    settings.alertsDollarFloorCents = settings.alertsDollarFloorCents
    #expect(settings.value(.alertsDollarFloorCents) == SettingsKey.alertsDollarFloorCents.spec.defaultValue)
    settings.alertsStaleMultiplier = settings.alertsStaleMultiplier
    #expect(settings.value(.alertsStaleMultiplier) == SettingsKey.alertsStaleMultiplier.spec.defaultValue)
    settings.alertsDriftThresholdPct = settings.alertsDriftThresholdPct
    #expect(settings.value(.alertsDriftThresholdPct) == SettingsKey.alertsDriftThresholdPct.spec.defaultValue)
    settings.alertsAnchorAgeDays = settings.alertsAnchorAgeDays
    #expect(settings.value(.alertsAnchorAgeDays) == SettingsKey.alertsAnchorAgeDays.spec.defaultValue)
    settings.alertsNotifyLow = settings.alertsNotifyLow
    #expect(settings.value(.alertsNotifyLow) == SettingsKey.alertsNotifyLow.spec.defaultValue)
    settings.alertsNotifyCritical = settings.alertsNotifyCritical
    #expect(settings.value(.alertsNotifyCritical) == SettingsKey.alertsNotifyCritical.spec.defaultValue)
    settings.alertsNotifyUnknown = settings.alertsNotifyUnknown
    #expect(settings.value(.alertsNotifyUnknown) == SettingsKey.alertsNotifyUnknown.spec.defaultValue)
    settings.alertsNotifyStale = settings.alertsNotifyStale
    #expect(settings.value(.alertsNotifyStale) == SettingsKey.alertsNotifyStale.spec.defaultValue)
    settings.alertsQuietHoursEnabled = settings.alertsQuietHoursEnabled
    #expect(settings.value(.alertsQuietHoursEnabled) == SettingsKey.alertsQuietHoursEnabled.spec.defaultValue)
  }

  @Test("typed accessors, part 3: each returns its 09 default and accepts a write")
  func accessorsPart3() {
    let settings = Self.makeSettings()
    settings.alertsQuietStart = settings.alertsQuietStart
    #expect(settings.value(.alertsQuietStart) == SettingsKey.alertsQuietStart.spec.defaultValue)
    settings.alertsQuietEnd = settings.alertsQuietEnd
    #expect(settings.value(.alertsQuietEnd) == SettingsKey.alertsQuietEnd.spec.defaultValue)
    settings.updateCheckEnabled = settings.updateCheckEnabled
    #expect(settings.value(.updateCheckEnabled) == SettingsKey.updateCheckEnabled.spec.defaultValue)
    settings.updateLastCheckedAt = settings.updateLastCheckedAt
    #expect(settings.value(.updateLastCheckedAt) == SettingsKey.updateLastCheckedAt.spec.defaultValue)
    settings.updateLatestSeen = settings.updateLatestSeen
    #expect(settings.value(.updateLatestSeen) == SettingsKey.updateLatestSeen.spec.defaultValue)
    settings.updateIgnoredVersion = settings.updateIgnoredVersion
    #expect(settings.value(.updateIgnoredVersion) == SettingsKey.updateIgnoredVersion.spec.defaultValue)
    settings.logLevel = settings.logLevel
    #expect(settings.value(.logLevel) == SettingsKey.logLevel.spec.defaultValue)
    settings.logRetentionDays = settings.logRetentionDays
    #expect(settings.value(.logRetentionDays) == SettingsKey.logRetentionDays.spec.defaultValue)
    settings.retentionHourlyDays = settings.retentionHourlyDays
    #expect(settings.value(.retentionHourlyDays) == SettingsKey.retentionHourlyDays.spec.defaultValue)
    settings.retentionRawHarnessDays = settings.retentionRawHarnessDays
    #expect(settings.value(.retentionRawHarnessDays) == SettingsKey.retentionRawHarnessDays.spec.defaultValue)
    settings.dbLastBackupAt = settings.dbLastBackupAt
    #expect(settings.value(.dbLastBackupAt) == SettingsKey.dbLastBackupAt.spec.defaultValue)
    settings.dbLastIntegrityCheckAt = settings.dbLastIntegrityCheckAt
    #expect(settings.value(.dbLastIntegrityCheckAt) == SettingsKey.dbLastIntegrityCheckAt.spec.defaultValue)
    settings.debugFixtureMode = settings.debugFixtureMode
    #expect(settings.value(.debugFixtureMode) == SettingsKey.debugFixtureMode.spec.defaultValue)
  }
}
