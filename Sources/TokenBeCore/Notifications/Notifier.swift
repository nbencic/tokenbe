import Foundation

/// One macOS notification (08 § Notifications): the account it is about, why, and its text. `Open` and
/// `Snooze 24 h` act on `accountID` and `provider`.
public struct AlertNotice: Sendable, Equatable {
  public enum Kind: String, Sendable, CaseIterable {
    case low, critical, unknown, stale
    /// `Send test notification` (Alerts tab).
    case test
  }

  public var accountID: String
  public var provider: ProviderID
  public var kind: Kind
  public var title: String
  public var body: String

  public init(accountID: String, provider: ProviderID, kind: Kind, title: String, body: String) {
    self.accountID = accountID
    self.provider = provider
    self.kind = kind
    self.title = title
    self.body = body
  }
}

/// The notifications seam (14 § 0.3): `UNNotifier` in the app, `RecordingNotifier` in tests. It lives in Core so
/// Core's `AlertCenter` and its tests can use it (E2E-4 runs in a Core test; Q-043).
public protocol Notifier: Sendable {
  /// Asks for authorization the first time (08: at the first band alert, not at launch); true when allowed.
  func authorize() async -> Bool
  /// Posts the notice now.
  func deliver(_ notice: AlertNotice) async throws
}
