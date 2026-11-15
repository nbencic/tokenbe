import Foundation
@testable import TokenBeCore

/// The test `Notifier` (14 § 0.3): records every notice; authorization answers `allow` and is counted.
actor RecordingNotifier: Notifier {
  private(set) var notices: [AlertNotice] = []
  private(set) var authorizationRequests = 0
  var allow: Bool
  var failing = false

  init(allow: Bool = true) {
    self.allow = allow
  }

  func setFailing(_ value: Bool) { failing = value }

  func authorize() async -> Bool {
    authorizationRequests += 1
    return allow
  }

  func deliver(_ notice: AlertNotice) async throws {
    if failing { throw StoreError.notFound("delivery") }
    notices.append(notice)
  }
}
