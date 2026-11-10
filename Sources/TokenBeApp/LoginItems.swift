import Foundation
import ServiceManagement
import TokenBeCore

/// The real login item: `SMAppService.mainApp` (09 § General).
@MainActor
final class SystemLoginItem: LoginItemService {
  var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
  func register() throws { try SMAppService.mainApp.register() }
  func unregister() throws { try SMAppService.mainApp.unregister() }
}

#if DEBUG
/// Debug-only, under `TOKENBE_TEST_ROOT`: a marker file stands in for the login item, so UI tests exercise the
/// toggle without registering the owner's real login item (Q-023). A fresh test root starts unregistered.
@MainActor
final class TestLoginItem: LoginItemService {
  private let marker: URL

  init(root: URL) {
    marker = root.appendingPathComponent("login-item-enabled")
  }

  var isEnabled: Bool { FileManager.default.fileExists(atPath: marker.path) }

  func register() throws {
    try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: marker)
  }

  func unregister() throws {
    try FileManager.default.removeItem(at: marker)
  }
}
#endif
