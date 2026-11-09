import Foundation
import ServiceManagement
import TokenBeCore

/// The app's startup steps in 04 order (later stages append steps) and the clean-terminate path.
@MainActor
final class Startup {
  /// Where the app keeps its files. Debug builds honor `TOKENBE_TEST_ROOT` so UI tests never touch the owner's
  /// real logs, sentinel or settings (Q-014); Release builds always use the 04/07/09 locations.
  struct Paths {
    let support: URL
    let logs: URL
    let settingsSuite: String

    static func current() -> Paths {
      #if DEBUG
      if let root = ProcessInfo.processInfo.environment[testRootVariable], !root.isEmpty {
        let base = URL(fileURLWithPath: root, isDirectory: true)
        return Paths(
          support: base.appendingPathComponent("Application Support/TokenBe", isDirectory: true),
          logs: base.appendingPathComponent("Logs/TokenBe", isDirectory: true),
          settingsSuite: SettingsSuite.uiTestsName
        )
      }
      #endif
      return Paths(
        support: RunningSentinel.defaultDirectory, logs: NDJSONSink.defaultDirectory,
        settingsSuite: SettingsSuite.name
      )
    }
  }

  nonisolated static let testRootVariable = "TOKENBE_TEST_ROOT"
  /// Debug-only, with `TOKENBE_TEST_ROOT`: `1` clears the UI-test settings suite before `Settings` loads (Q-020).
  nonisolated static let testResetSettingsVariable = "TOKENBE_TEST_RESET_SETTINGS"

  private let paths = Paths.current()
  private lazy var sentinel = RunningSentinel(directory: paths.support)
  private var sink: NDJSONSink?
  /// The composition root, available once the logging step has run.
  private(set) var environment: AppEnvironment?
  private var retentionWatcher: Task<Void, Never>?

  func run() async {
    let sequence = StartupSequence(steps: [
      StartupStep("logging") { [self] in try await startLogging() }
    ])
    await sequence.run()
  }

  /// 04 step 1: file sink first, then OSLog; `app.launch`; previous-crash check; crash handler; sentinel.
  private func startLogging() async throws {
    let version = LogPipeline.bundleVersion()
    let ring = CrashRing(version: version)
    let fileSink = NDJSONSink(directory: paths.logs, crashTarget: true)
    sink = fileSink
    let osLog = OSLogSink()
    Log.configure(sinks: [fileSink, osLog], clock: ContinuousClock(), crashRing: ring, version: version)
    CrashHandler.install(ring: ring)
    let info = Bundle.main.infoDictionary
    Log.info(.appLaunch, cat: .app, msg: "launch", ctx: [
      "version": .string(info?["CFBundleShortVersionString"] as? String ?? "dev"),
      "build": .string(info?["CFBundleVersion"] as? String ?? "0"),
      "macOS": .string(ProcessInfo.processInfo.operatingSystemVersionString),
      "lowPower": .bool(ProcessInfo.processInfo.isLowPowerModeEnabled),
      "launchAtLogin": .bool(SMAppService.mainApp.status == .enabled),
      "locale": .string(Locale.current.identifier),
      "timezone": .string(TimeZone.current.identifier)
    ])
    if sentinel.wasUnclean() {
      Log.fault(.crashPreviousLaunch, cat: .crash, msg: "previous run did not terminate cleanly", ctx: [
        "signal_or_exception": "unknown", "breadcrumbs_attached": false
      ])
    }
    try sentinel.markRunning()
    #if DEBUG
    if ProcessInfo.processInfo.environment[Self.testResetSettingsVariable] == "1" {
      _ = SettingsSuite.resetUITests(named: paths.settingsSuite)
    }
    #endif
    let current = Settings(store: SettingsSuite.store(named: paths.settingsSuite))
    environment = AppEnvironment(settings: current, clock: ContinuousClock(), logSinks: [fileSink, osLog])
    await fileSink.setRetentionDays(current.logRetentionDays)
    retentionWatcher = Task { [weak self] in
      for await key in current.changes where key == .logRetentionDays {
        await self?.sink?.setRetentionDays(current.logRetentionDays)
      }
    }
  }

  /// `app.terminate {reason}`, sentinel removed, then the log drained (07).
  func terminate(reason: String) async {
    Log.info(.appTerminate, cat: .app, msg: "terminate", ctx: ["reason": .string(reason)])
    retentionWatcher?.cancel()
    do {
      try sentinel.markClean()
    } catch {
      Log.error(.appTerminate, cat: .app, msg: "could not remove the running sentinel", err: error, ctx: [
        "reason": .string(reason)
      ])
    }
    await Log.current?.shutdown()
  }
}
