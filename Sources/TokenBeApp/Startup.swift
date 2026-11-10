import AppKit
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
    /// Debug-only `TOKENBE_TEST_ROOT`; nil in normal runs.
    let testRoot: URL?

    static func current() -> Paths {
      #if DEBUG
      if let root = ProcessInfo.processInfo.environment[testRootVariable], !root.isEmpty {
        let base = URL(fileURLWithPath: root, isDirectory: true)
        return Paths(
          support: base.appendingPathComponent("Application Support/TokenBe", isDirectory: true),
          logs: base.appendingPathComponent("Logs/TokenBe", isDirectory: true),
          settingsSuite: SettingsSuite.uiTestsName, testRoot: base
        )
      }
      #endif
      return Paths(
        support: RunningSentinel.defaultDirectory, logs: NDJSONSink.defaultDirectory,
        settingsSuite: SettingsSuite.name, testRoot: nil
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
  private var loginItem: LoginItemController?
  /// Set when step 2 failed; launch stops with `FatalErrorAlert` (03 § Migrations).
  private(set) var databaseFailure: DatabaseOpenError?
  /// Set when step 2 repaired a corrupt database; the user is told once startup has finished (03 § Durability).
  private(set) var databaseRecovery: DatabaseRecovery?
  /// `app.terminate {reason}` for the next terminate: `quit`, or `database` after a fatal alert.
  private(set) var terminationReason = "quit"

  /// Returns false when launch must stop: the fatal alert has been shown and the app is terminating.
  @discardableResult
  func run() async -> Bool {
    let sequence = StartupSequence(steps: [
      StartupStep("logging") { [self] in try await startLogging() },
      StartupStep("database") { [self] in try await openDatabase() },
      StartupStep("login item") { [self] in startLoginItem() }
    ])
    let succeeded = await sequence.run()
    if succeeded, let recovery = databaseRecovery {
      // Shown after startup so the modal never holds up later steps (Q-024).
      FatalErrorAlert.showRecovered(recovery)
    }
    guard succeeded else {
      if let databaseFailure {
        FatalErrorAlert.show(databaseFailure)
        terminationReason = "database"
        NSApp.terminate(nil)
        return false
      }
      return true
    }
    return true
  }

  /// 04 step 2: open `tokenbe.sqlite` with 03's PRAGMAs, `quick_check`, migrate (`DatabaseOpener`). A corrupt
  /// database is repaired on the way and the user is told where the damaged copy went.
  private func openDatabase() async throws {
    do {
      let opened = try await DatabaseOpener.open(directory: paths.support)
      environment?.repository = GRDBRepository(database: opened.database)
      databaseRecovery = opened.recovery
    } catch {
      databaseFailure = error as? DatabaseOpenError ?? DatabaseOpenError(
        migration: nil, message: String(describing: error),
        databasePath: paths.support.appendingPathComponent(AppDatabase.fileName).path,
        backupPath: paths.support.appendingPathComponent(AppDatabase.fileName + ".bak").path
      )
      throw error
    }
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
    environment = AppEnvironment(
      settings: current, clock: ContinuousClock(), logSinks: [fileSink, osLog], logsDirectory: paths.logs,
      transport: Transports.make(
        fixtureMode: current.debugFixtureMode,
        version: info?["CFBundleShortVersionString"] as? String ?? "dev"
      ),
      registry: ProviderRegistry(adapters: [OpenAIAdapter()])
    )
    await fileSink.setRetentionDays(current.logRetentionDays)
    retentionWatcher = Task { [weak self] in
      for await key in current.changes where key == .logRetentionDays {
        await self?.sink?.setRetentionDays(current.logRetentionDays)
      }
    }
  }

  /// 09 `tb.general.launchAtLogin`: the setting mirrors the system's login item, then drives it. UI tests get a
  /// marker file in the test root instead of the owner's real login item (Q-023).
  private func startLoginItem() {
    guard let settings = environment?.settings else { return }
    let service: any LoginItemService
    #if DEBUG
    if let root = paths.testRoot {
      service = TestLoginItem(root: root)
    } else {
      service = SystemLoginItem()
    }
    #else
    service = SystemLoginItem()
    #endif
    let controller = LoginItemController(settings: settings, service: service)
    controller.start()
    loginItem = controller
  }

  /// `app.terminate {reason}`, sentinel removed, then the log drained (07).
  func terminate(reason: String) async {
    Log.info(.appTerminate, cat: .app, msg: "terminate", ctx: ["reason": .string(reason)])
    retentionWatcher?.cancel()
    loginItem?.stop()
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
