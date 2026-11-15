import Foundation
import TokenBeCore

/// Which `Notifier` the app uses (14 § 0.3): `UNNotifier`, or under a DEBUG `TOKENBE_TEST_ROOT` the `FileNotifier`
/// that writes `<root>/notifications.ndjson` (Q-043). The `Notifier` protocol itself lives in Core
/// (`TokenBeCore/Notifications/Notifier.swift`) so `AlertCenter` and its tests can use it.
enum Notifiers {
  @MainActor
  static func make(testRoot: URL?) -> (any Notifier, UNNotifier?) {
    #if DEBUG
    if let testRoot { return (FileNotifier(file: testRoot.appendingPathComponent("notifications.ndjson")), nil) }
    #endif
    let system = UNNotifier()
    return (system, system)
  }
}
