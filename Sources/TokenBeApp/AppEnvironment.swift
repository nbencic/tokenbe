import SwiftUI
import TokenBeCore

/// The composition root (14 § 0.3, D-composition-root): every seam the app uses, assembled once by `Startup`
/// after logging is configured (04 step 1). Grows stage by stage.
struct AppEnvironment {
  /// The process's only `Settings` instance.
  let settings: TokenBeCore.Settings
  let clock: ContinuousClock
  let logSinks: [any LogSink]
  /// Where the NDJSON log lives (07; a test root's `Logs/TokenBe` in UI tests), for `Open log folder`.
  let logsDirectory: URL
}

extension EnvironmentValues {
  /// Nil until startup step 1 has run.
  @Entry var appEnvironment: AppEnvironment?
}
