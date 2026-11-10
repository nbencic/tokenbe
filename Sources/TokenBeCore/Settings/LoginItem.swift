/// The system's login-item registration for TokenBe (`SMAppService.mainApp` in the app). A seam, so tests and UI
/// tests never register the owner's real login item (Q-023).
@MainActor
public protocol LoginItemService: AnyObject {
  /// True when the system will launch TokenBe at login.
  var isEnabled: Bool { get }
  func register() throws
  func unregister() throws
}

/// Keeps `tb.general.launchAtLogin` and the system's login item in agreement (09 § General).
/// - At launch the system wins: when they differ, the setting is changed to match, logged with `source=system`.
/// - When the user changes the setting, the login item is registered or unregistered. A failure logs
///   `app.login_item_failed` and sets the toggle back to what the system actually has.
@MainActor
public final class LoginItemController {
  private let settings: Settings
  private let service: any LoginItemService
  private let pipeline: LogPipeline?
  private var watcher: Task<Void, Never>?

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(settings: Settings, service: any LoginItemService, logPipeline: LogPipeline? = nil) {
    self.settings = settings
    self.service = service
    self.pipeline = logPipeline
  }

  /// Mirrors the system's status into the setting (04 startup), then follows the setting's changes.
  public func start() {
    mirrorSystemStatus()
    let changes = settings.changes
    watcher = Task { [weak self] in
      for await key in changes where key == .generalLaunchAtLogin {
        self?.apply()
      }
    }
  }

  public func stop() {
    watcher?.cancel()
    watcher = nil
  }

  /// The setting follows the system when they differ (`source=system`).
  public func mirrorSystemStatus() {
    let actual = service.isEnabled
    if settings.generalLaunchAtLogin != actual {
      settings.set(.generalLaunchAtLogin, .bool(actual), source: .system)
    }
  }

  /// Makes the system match the setting.
  public func apply() {
    let wanted = settings.generalLaunchAtLogin
    guard wanted != service.isEnabled else { return }
    do {
      if wanted {
        try service.register()
      } else {
        try service.unregister()
      }
    } catch {
      let ctx: [String: LogValue] = ["wanted": .bool(wanted)]
      if let pipeline {
        pipeline.emit(.error, .appLoginItemFailed, cat: .app, msg: "login item change failed", err: error, ctx: ctx)
      } else {
        Log.error(.appLoginItemFailed, cat: .app, msg: "login item change failed", err: error, ctx: ctx)
      }
      mirrorSystemStatus()
    }
  }
}
