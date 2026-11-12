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
  /// Every provider request goes through this (14 § 0.3): fixtures in DEBUG with `tb.debug.fixtureMode`, else the
  /// network. Chosen once at launch, so changing the setting takes effect at the next launch (Q-029).
  let transport: any HTTPTransport
  /// The adapters this build has (PM-3.3-2); onboarding (3.5) offers `registry.availableForOnboarding`.
  let registry: ProviderRegistry
  /// Where API keys live: the login keychain, or a DEBUG file store inside `TOKENBE_TEST_ROOT` (PM-3.2-1, Q-030).
  let keyStore: any KeyStore
  /// The store (03), set by startup step 2; nil only if that step failed, in which case the app quits.
  var repository: (any Repository)?
  /// Runs every account's jobs on their own (04 § Scheduler; 14 § Stage 4.1). Set by the `scheduler` startup step;
  /// nil before it, or if step 2 failed.
  var coordinator: PollCoordinator<ContinuousClock>?

  /// Onboarding, `Replace key…`, `Test`, `Remove account…` and startup step 3 (14 § Stage 3.5). Nil before step 2.
  var lifecycle: AccountLifecycle? {
    repository.map {
      AccountLifecycle(repository: $0, keyStore: keyStore, registry: registry, transport: transport)
    }
  }
}

extension EnvironmentValues {
  /// Nil until startup step 1 has run.
  @Entry var appEnvironment: AppEnvironment?
}
