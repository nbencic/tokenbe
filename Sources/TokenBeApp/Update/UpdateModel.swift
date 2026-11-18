import AppKit
import Observation
import TokenBeCore

/// 02 § Update check in the app (14 § Stage 9.4): the daily activity's `update check` step, and the `Update
/// available` badge's state for Privacy, the Overview and the popover (09 `tb.update.*`).
@MainActor @Observable
final class UpdateModel {
  @ObservationIgnored private let checker: UpdateChecker
  @ObservationIgnored private let settings: TokenBeCore.Settings
  /// The bundle's `CFBundleShortVersionString`.
  let current: String
  /// The latest check's `html_url`, when it was a TokenBe release page; kept for this run only (Q-058).
  private(set) var page: URL?

  init(settings: TokenBeCore.Settings, transport: any HTTPTransport,
       current: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") {
    self.settings = settings
    self.current = current
    checker = UpdateChecker(transport: transport)
  }

  /// The version the badge offers, or nil: checks are on, and `tb.update.latestSeen` is newer than the bundle and
  /// not the skipped one (09).
  var available: String? {
    guard settings.updateCheckEnabled,
          UpdateChecker.isUpdateAvailable(latestSeen: settings.updateLatestSeen, current: current,
                                          ignored: settings.updateIgnoredVersion) else { return nil }
    return settings.updateLatestSeen
  }

  /// The release page the badge opens: this run's `html_url`, else the page of the version seen earlier.
  var releasePage: URL? { page ?? UpdateChecker.page(version: settings.updateLatestSeen) }

  /// The daily step: at most one GET per UTC day (08's caption), only while `tb.update.checkEnabled` is on. A failed
  /// check is logged by the checker and changes nothing but `tb.update.lastCheckedAt`.
  func check(now: Date = Date()) async {
    guard settings.updateCheckEnabled,
          UpdateChecker.isDue(lastCheckedAt: settings.updateLastCheckedAt, now: now) else { return }
    settings.updateLastCheckedAt = now.timeIntervalSince1970
    if case .checked(let latest, let page, _) = await checker.check(current: current) {
      settings.updateLatestSeen = latest
      self.page = page
    }
  }

  /// `Skip this version` (09 `tb.update.ignoredVersion`).
  func skip() {
    settings.updateIgnoredVersion = settings.updateLatestSeen
  }

  /// Opens the release page in the browser. No download, no install (D-no-sparkle).
  func openReleasePage() {
    guard let url = releasePage else { return }
    NSWorkspace.shared.open(url)
  }
}
