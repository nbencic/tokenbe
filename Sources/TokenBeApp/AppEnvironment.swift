import SwiftUI
import TokenBeCore

/// The composition root (14 § 0.3, D-composition-root): every seam the app uses, assembled once by `Startup`
/// after logging is configured (04 step 1). Grows stage by stage.
struct AppEnvironment {
  /// The process's only `Settings` instance.
  let settings: TokenBeCore.Settings
  let clock: ContinuousClock
  let logSinks: [any LogSink]
}

extension EnvironmentValues {
  /// Nil until startup step 1 has run.
  @Entry var appEnvironment: AppEnvironment?
}
