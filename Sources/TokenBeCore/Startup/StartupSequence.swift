/// One named step of the startup sequence (04 § Startup sequence). The app supplies the closures.
public struct StartupStep: Sendable {
  public let name: String
  public let run: @MainActor @Sendable () async throws -> Void

  public init(_ name: String, run: @escaping @MainActor @Sendable () async throws -> Void) {
    self.name = name
    self.run = run
  }
}

/// Runs startup steps strictly in order and logs one `app.launch {startup_step}` record per step (14 § Stage 0.4).
/// The first failing step is logged at `error` and stops the sequence (04: "Any failure → alert, stop").
@MainActor
public final class StartupSequence {
  public private(set) var completed: [String] = []
  private let steps: [StartupStep]
  private let pipeline: LogPipeline?

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(steps: [StartupStep], logPipeline: LogPipeline? = nil) {
    self.steps = steps
    self.pipeline = logPipeline
  }

  /// Returns true when every step succeeded.
  @discardableResult
  public func run() async -> Bool {
    for step in steps {
      do {
        try await step.run()
      } catch {
        log(.error, msg: "startup step failed", step: step.name, err: error)
        return false
      }
      completed.append(step.name)
      log(.info, msg: "startup step done", step: step.name, err: nil)
    }
    return true
  }

  private func log(_ level: LogLevel, msg: String, step: String, err: (any Error)?) {
    let ctx: [String: LogValue] = ["startup_step": .string(step)]
    if let pipeline {
      pipeline.emit(level, .appLaunch, cat: .app, msg: msg, err: err, ctx: ctx)
    } else if level == .error {
      Log.error(.appLaunch, cat: .app, msg: msg, err: err, ctx: ctx)
    } else {
      Log.info(.appLaunch, cat: .app, msg: msg, ctx: ctx)
    }
  }
}
