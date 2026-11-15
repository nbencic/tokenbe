import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 6.1 Tests, `OverviewTotalsTests`: a direct account's remaining comes from its latest balance reading
/// in its own currency, without `≈` or `±` (05 § Remaining); an unavailable account is `critical`
/// (D-deepseek-unavailable); cross-account totals sum USD only and count the rest as `+ N non-USD` (05 § Currency).
@Suite struct OverviewTotalsTests {
  typealias Harness = DeepSeekHarness

  @Test("a CN¥ DeepSeek account: remaining from the CNY snapshot, estimate band 0, formatted CN¥ without ≈")
  func directCNY() async throws {
    let env = try await Harness(currency: "CNY")
    await env.on("cny")
    #expect(await env.run() == .succeeded(rows: 2))
    let summary = try #require(try await env.summaries().first)
    #expect(summary.mode == .direct)
    #expect(summary.currency == .cny)
    #expect(summary.remainingCents == 5_679)
    #expect(summary.estimateBandCents == 0)
    #expect(!summary.providerUnavailable)
    // No harness spend yet (7.2): no burn, so no runway, so the band waits (`Collecting…`, 08).
    #expect(summary.burn7dCents == nil && summary.runwayMin == nil && summary.band == .unknown)
    let text = Formatters.remaining(Money(cents: summary.remainingCents ?? 0, currency: summary.currency),
                                    hideCents: false, locale: Locale(identifier: "en_US_POSIX"))
    #expect(text == "CN¥56.79")
  }

  @Test("the account's currency picks the snapshot, whatever the entry order; none in it → no remaining")
  func currencyPicksSnapshot() {
    let reading = [
      Harness.snapshot("USD", 150, granted: nil, toppedUp: nil, available: true),
      Harness.snapshot("CNY", 5_679, granted: nil, toppedUp: nil, available: true)
    ]
    let inputs = SummaryInputs(accounts: [], balances: reading)
    #expect(Remaining.cents(mode: .direct, accountID: Harness.accountID, currency: .cny, inputs: inputs,
                            spendSinceAnchor: nil) == 5_679)
    #expect(Remaining.cents(mode: .direct, accountID: Harness.accountID, currency: .usd, inputs: inputs,
                            spendSinceAnchor: nil) == 150)
    let usdOnly = SummaryInputs(accounts: [], balances: [reading[0]])
    #expect(Remaining.cents(mode: .direct, accountID: Harness.accountID, currency: .cny, inputs: usdOnly,
                            spendSinceAnchor: nil) == nil)
  }

  @Test("unavailable: the balance still shows, the band is critical with no runway, the banner says why")
  func unavailable() async throws {
    let env = try await Harness()
    await env.on("unavailable")
    #expect(await env.run() == .succeeded(rows: 1))
    let summary = try #require(try await env.summaries().first)
    #expect(summary.providerUnavailable)
    #expect(summary.remainingCents == 0)
    #expect(summary.runwayMin == nil)
    #expect(summary.band == .critical)
    #expect(AlertBannerPick.pick([summary])?.kind == .unavailable)
    #expect(AlertPolicy.notice(summary, kind: .critical, hideCents: true).body
      == "DeepSeek: the provider reports the account unavailable.")
    #expect(BandRecorder.inputs(summary).json.contains("\"unavailable\":1"))
  }

  @Test("unavailable outranks auto-reload and a healthy runway; available leaves the band to the runway")
  func unavailableOrder() {
    let thresholds = BandThresholds()
    let reload = AutoReload(belowCents: 10_000, toCents: 20_000)
    #expect(BandEvaluator.band(.init(mode: .direct, remaining: 5_000, runwayMin: 90 * 86_400, autoReload: reload,
                                     providerUnavailable: true), thresholds: thresholds).band == .critical)
    #expect(BandEvaluator.band(.init(mode: .direct, remaining: nil, providerUnavailable: true),
                               thresholds: thresholds).band == .critical)
    #expect(BandEvaluator.band(.init(mode: .direct, remaining: 50_000, runwayMin: 90 * 86_400),
                               thresholds: thresholds).band == .healthy)
    // Only the latest reading counts: a later available reading clears it.
    let inputs = SummaryInputs(accounts: [], balances: [
      Harness.snapshot("USD", 0, granted: nil, toppedUp: nil, available: false, ts: "2026-11-10T11:00:00.000Z"),
      Harness.snapshot("USD", 900, granted: nil, toppedUp: nil, available: true)
    ])
    #expect(!Remaining.providerUnavailable(accountID: Harness.accountID, inputs: inputs))
  }

  @Test("Overview: USD remaining summed, the CN¥ account counted as non-USD; spend totals likewise")
  func mixedCurrencies() {
    var openai = AccountSummary(id: "o", provider: .openai, label: "OpenAI", mode: .anchored, currency: .usd)
    openai.remainingCents = 31_200
    openai.estimateBandCents = 900
    openai.rangeSpend = SpendFigure(cents: 310, isEstimate: true)
    var deepseek = AccountSummary(id: "d", provider: .deepseek, label: "DeepSeek", mode: .direct, currency: .cny)
    deepseek.remainingCents = 5_679
    deepseek.estimateBandCents = 0
    deepseek.rangeSpend = SpendFigure(cents: 99, isEstimate: true)
    let total = OverviewTotals.remaining([openai, deepseek])
    #expect(total.cents == 31_200)
    #expect(total.bandCents == 900)
    #expect(total.usdAccounts == 1)
    #expect(total.nonUSD == 1)
    let spend = Spend.totalUSD([openai, deepseek])
    #expect(spend.spend.cents == 310)
    #expect(spend.nonUSD == 1)
  }
}
