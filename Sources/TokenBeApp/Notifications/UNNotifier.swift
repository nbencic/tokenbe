import AppKit
import Foundation
import TokenBeCore
@preconcurrency import UserNotifications

/// The production `Notifier` (14 § 0.3, § Stage 5.4 step 1): `UNUserNotificationCenter`, category `band` with the
/// actions `open` (`Open`) and `snooze` (`Snooze 24 h`). Authorization is asked at the first alert, not at launch
/// (08). `Open` shows the account's page; `Snooze 24 h` sets 09 `tb.alerts.snoozedUntil.<provider>` to now + 24 h.
final class UNNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
  static let category = "band"
  static let openAction = "open"
  static let snoozeAction = "snooze"

  /// What the actions do; set by the app delegate once the model exists.
  @MainActor var onOpen: ((String) -> Void)?
  @MainActor var onSnooze: ((ProviderID) -> Void)?

  @MainActor
  override init() {
    super.init()
    let center = UNUserNotificationCenter.current()
    center.setNotificationCategories([UNNotificationCategory(
      identifier: Self.category,
      actions: [UNNotificationAction(identifier: Self.openAction, title: CoreStrings.Alerts.open, options: [.foreground]),
                UNNotificationAction(identifier: Self.snoozeAction, title: CoreStrings.Alerts.snooze, options: [])],
      intentIdentifiers: []
    )])
    center.delegate = self
  }

  func authorize() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    switch status {
    case .authorized, .provisional: return true
    case .denied: return false
    default:
      do {
        return try await center.requestAuthorization(options: [.alert, .sound])
      } catch {
        Log.warn(.uiNotificationDenied, cat: .ui, msg: "notification authorization failed", err: error)
        return false
      }
    }
  }

  func deliver(_ notice: AlertNotice) async throws {
    let content = UNMutableNotificationContent()
    content.title = notice.title
    content.body = notice.body
    content.categoryIdentifier = Self.category
    content.userInfo = ["account": notice.accountID, "provider": notice.provider.rawValue]
    try await UNUserNotificationCenter.current().add(UNNotificationRequest(
      identifier: "\(notice.accountID).\(notice.kind.rawValue).\(UUID().uuidString)", content: content, trigger: nil
    ))
  }

  /// Notifications show while TokenBe is frontmost too.
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
    async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    let info = response.notification.request.content.userInfo
    let account = info["account"] as? String ?? ""
    let provider = (info["provider"] as? String).flatMap(ProviderID.init(rawValue:))
    let action = response.actionIdentifier
    await MainActor.run {
      if action == Self.snoozeAction, let provider {
        onSnooze?(provider)
      } else if action == Self.openAction || action == UNNotificationDefaultActionIdentifier, !account.isEmpty {
        onOpen?(account)
      }
    }
  }
}

#if DEBUG
/// UI tests (`TOKENBE_TEST_ROOT`): notices are appended as JSON lines to `<root>/notifications.ndjson` and
/// authorization is granted, so no system prompt appears and the test can read what was sent (Q-043).
struct FileNotifier: Notifier {
  let file: URL

  func authorize() async -> Bool { true }

  func deliver(_ notice: AlertNotice) async throws {
    let object: [String: String] = ["account": notice.accountID, "provider": notice.provider.rawValue,
                                    "kind": notice.kind.rawValue, "body": notice.body]
    var line = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    line.append(0x0A)
    if !FileManager.default.fileExists(atPath: file.path) {
      FileManager.default.createFile(atPath: file.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: file)
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: line)
      try handle.close()
    } catch {
      Log.error(.uiError, cat: .ui, msg: "test notification not written", err: error, ctx: ["view": "notification"])
      throw error
    }
  }
}
#endif
