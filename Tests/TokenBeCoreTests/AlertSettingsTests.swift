import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 09 § Alerts read into Core (14 § Stages 5.3–5.4): the band thresholds and the notification settings follow the
/// stored keys, snooze included; the builder's stored-band and direct-balance paths; deleting a user ledger row.
@MainActor @Suite struct AlertSettingsTests {
  static func settings() -> Settings {
    Settings(store: InMemorySettingsStore(), logPipeline: LogPipeline(sinks: [], version: "test"))
  }

  @Test("BandThresholds and AlertSettings read 09's keys, defaults first")
  func readsSettings() {
    let settings = Self.settings()
    #expect(BandThresholds(settings) == BandThresholds())
    #expect(AlertSettings(settings) == AlertSettings())
    settings.alertsWatchDays = 30
    settings.alertsDollarFloorCents = 1_000
    settings.alertsNotifyStale = false
    settings.alertsQuietStart = "22:15"
    settings.alertsQuietEnd = "06:45"
    settings.uiHideCents = false
    settings.setSnoozedUntil(.openai, 1_794_400_000)
    let thresholds = BandThresholds(settings)
    #expect(thresholds.watchDays == 30)
    #expect(thresholds.dollarFloorCents == 1_000)
    let alerts = AlertSettings(settings)
    #expect(!alerts.notifyStale)
    #expect(alerts.quietStart == 22 * 60 + 15)
    #expect(alerts.quietEnd == 6 * 60 + 45)
    #expect(!alerts.hideCents)
    #expect(alerts.snoozedUntil[.openai] == Date(timeIntervalSince1970: 1_794_400_000))
    #expect(alerts.snoozedUntil[.xai] == nil)
  }

  @Test("the builder takes band_state's since, and a direct balance has M = 0")
  func builderPaths() {
    var record = OpenAIHarness.account
    record.balanceMode = "direct"
    let inputs = SummaryInputs(
      accounts: [record],
      pollStates: [PollStateSummary(accountId: record.id, job: "balance", lastSuccessAt: "2026-11-10T11:00:00.000Z")],
      balances: [BalanceSnapshotRecord(accountId: record.id, ts: "2026-11-10T11:00:00.000Z", currency: "USD",
                                       amountCents: 4_200, grantedCents: nil, toppedUpCents: nil, isAvailable: nil)],
      bandStates: [BandStateRecord(accountId: record.id, band: "healthy", since: "2026-11-09T00:00:00.000Z",
                                   inputsJson: "{}")]
    )
    let summary = AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: OpenAIHarness.now)).first
    #expect(summary?.bandSince == DBTime.date("2026-11-09T00:00:00.000Z"))
    #expect(summary?.remainingCents == 4_200)
    #expect(summary?.estimateBandCents == 0)
  }

  @Test("AccountLifecycle deletes a user ledger row")
  func deleteLedgerEvent() async throws {
    let harness = try await OpenAIHarness()
    let lifecycle = AccountLifecycle(repository: harness.repository, keyStore: harness.keys,
                                     registry: ProviderRegistry(adapters: [harness.adapter]),
                                     transport: harness.transport, logPipeline: harness.store.pipeline,
                                     now: harness.date.provider)
    try await lifecycle.addTopUp(OpenAIHarness.account, cents: 500)
    let id = try await harness.database.read { db in try String.fetchOne(db, sql: "SELECT id FROM ledger_event") }
    #expect(try await lifecycle.deleteLedgerEvent(id: try #require(id)))
    #expect(try await lifecycle.deleteLedgerEvent(id: try #require(id)) == false)
  }
}
