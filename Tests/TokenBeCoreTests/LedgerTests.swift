import Foundation
import Testing
@testable import TokenBeCore

/// 05 § Remaining, § Estimate band, § Runway, § Bands (11 `LedgerTests`, 14 § Stage 5.3): every row of
/// `expected/ledger.csv` (remaining, burn_7d, burn_today, M, auto-reload → runway_min, band, by hand), remaining from
/// an anchor and top-ups, `spend_since_anchor`, `M`, and the summary builder end to end on the real database.
@Suite struct LedgerTests {
  struct Row: Sendable, CustomTestStringConvertible {
    var name: String
    var remaining: Int64?
    var burn7d: Int64?
    var burnToday: Int64?
    var estimateBand: Int64
    var reloadBelow: Int64?
    var runwayMin: Int64?
    var band: Band
    var testDescription: String { name }
  }

  static func rows() throws -> [Row] {
    let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
    let text = try String(contentsOf: root.appendingPathComponent("Fixtures/expected/ledger.csv"), encoding: .utf8)
    return try text.split(separator: "\n").dropFirst().map { line in
      let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      guard fields.count == 8, let band = Band(rawValue: fields[7]), let estimate = Int64(fields[4]) else {
        throw StoreError.notFound("bad ledger.csv line: \(line)")
      }
      return Row(name: fields[0], remaining: Int64(fields[1]), burn7d: Int64(fields[2]), burnToday: Int64(fields[3]),
                 estimateBand: estimate, reloadBelow: Int64(fields[5]), runwayMin: Int64(fields[6]), band: band)
    }
  }

  @Test("ledger.csv covers every band and every nil combination")
  func coverage() throws {
    let rows = try Self.rows()
    #expect(rows.count == 16)
    #expect(Set(rows.map(\.band)) == Set(Band.allCases))
    #expect(rows.contains { $0.remaining == nil } && rows.contains { $0.burn7d == nil && $0.burnToday == nil })
  }

  @Test("each ledger.csv row gives its runway_min and band", arguments: try LedgerTests.rows())
  func csvRow(_ row: Row) {
    let paces = Runway.paces(remaining: row.remaining, burn7d: row.burn7d, burnToday: row.burnToday)
    #expect(paces.minimum.map { Int64($0) } == row.runwayMin)
    let result = BandEvaluator.band(BandEvaluator.Inputs(
      mode: .anchored, remaining: row.remaining, estimateBand: row.estimateBand, burn7d: row.burn7d,
      runwayMin: paces.minimum, autoReload: row.reloadBelow.map { AutoReload(belowCents: $0, toCents: nil) }
    ), thresholds: BandThresholds())
    #expect(result.band == row.band)
    #expect(result.needsReanchor == (row.name == "negative past one day of burn (V1)"))
  }

  @Test("spend_only is unknown; thresholds come from 09")
  func modesAndThresholds() {
    let spendOnly = BandEvaluator.band(BandEvaluator.Inputs(mode: .spendOnly, remaining: 10_000, runwayMin: 1e9),
                                       thresholds: BandThresholds())
    #expect(spendOnly.band == .unknown)
    let tight = BandThresholds(watchDays: 30, lowDays: 20, criticalDays: 10, dollarFloorCents: 0)
    let inputs = BandEvaluator.Inputs(mode: .direct, remaining: 10_000, runwayMin: 15 * 86_400)
    #expect(BandEvaluator.band(inputs, thresholds: tight).band == .low)
    #expect(BandEvaluator.band(inputs, thresholds: BandThresholds()).band == .healthy)
  }

  @Test("runway: half a day, and the paces")
  func runwayPaces() {
    let paces = Runway.paces(remaining: 500, burn7d: 1_000, burnToday: nil)
    #expect(paces.sevenDay == 43_200)
    #expect(paces.today == nil)
    #expect(Runway.paces(remaining: nil, burn7d: 1, burnToday: 1).minimum == nil)
  }

  // MARK: - Remaining and M

  static let account = "acct"

  static func event(_ kind: String, _ cents: Int64?, _ ts: String, id: String = UUID().uuidString,
                    source: String = "user") -> LedgerEventRecord {
    LedgerEventRecord(id: id, accountId: account, ts: ts, kind: kind, amountCents: cents, currency: "USD", note: nil,
                      source: source)
  }

  @Test("remaining: the latest anchor + top-ups after it − spend since it; direct uses the latest balance")
  func remaining() {
    let events = [
      Self.event("anchor", 5_000, "2026-11-01T00:00:00.000Z", id: "a"),
      Self.event("topup", 9_999, "2026-10-31T00:00:00.000Z"),
      Self.event("anchor", 10_000, "2026-11-05T09:00:00.000Z", id: "b"),
      Self.event("topup", 2_500, "2026-11-06T00:00:00.000Z"),
      Self.event("note", nil, "2026-11-07T00:00:00.000Z")
    ]
    let inputs = SummaryInputs(accounts: [], ledgerEvents: events, balances: [
      BalanceSnapshotRecord(accountId: Self.account, ts: "2026-11-09T00:00:00.000Z", currency: "USD", amountCents: 700,
                            grantedCents: nil, toppedUpCents: nil, isAvailable: nil)
    ])
    #expect(Remaining.anchor(accountID: Self.account, events: events)?.id == "b")
    #expect(Remaining.cents(mode: .anchored, accountID: Self.account, currency: .usd, inputs: inputs, spendSinceAnchor: 1_200) == 11_300)
    #expect(Remaining.cents(mode: .anchored, accountID: Self.account, currency: .usd, inputs: inputs, spendSinceAnchor: nil) == nil)
    #expect(Remaining.cents(mode: .direct, accountID: Self.account, currency: .usd, inputs: inputs, spendSinceAnchor: nil) == 700)
    #expect(Remaining.cents(mode: .spendOnly, accountID: Self.account, currency: .usd, inputs: inputs, spendSinceAnchor: 0) == nil)
    #expect(Remaining.cents(mode: .anchored, accountID: "other", currency: .usd, inputs: inputs, spendSinceAnchor: 0) == nil)
  }

  @Test("M: drift 3 %, unreported lag, unpriced, age factor; each term rounds up")
  func estimateBand() {
    var inputs = EstimateBand.Inputs(spendSinceAnchor: 10_000, burn7d: 1_000, usageLagSeconds: 300,
                                     unpricedCents: 50, anchorAgeSeconds: 0, anchorAgeDays: 30)
    // 300 + ceil(1000 × 300 / 86400 = 3.47) = 4 + 50 = 354.
    #expect(EstimateBand.cents(inputs) == 354)
    inputs.anchorAgeSeconds = 30 * 86_400
    #expect(EstimateBand.cents(inputs) == 531)   // × 1.5
    inputs.anchorAgeSeconds = 61 * 86_400
    #expect(EstimateBand.cents(inputs) == 708)   // × 2
    let tiny = EstimateBand.Inputs(spendSinceAnchor: 1, burn7d: nil, usageLagSeconds: 0, unpricedCents: 0,
                                   anchorAgeSeconds: 0, anchorAgeDays: 30)
    #expect(EstimateBand.cents(tiny) == 1)
    let negative = EstimateBand.Inputs(spendSinceAnchor: -50, burn7d: -5, usageLagSeconds: -1, unpricedCents: -1,
                                       anchorAgeSeconds: -1, anchorAgeDays: 0)
    #expect(EstimateBand.cents(negative) == 0)
  }

  @Test("spend since anchor: later days by the daily rule plus the anchor day's remainder")
  func sinceAnchor() {
    let summary = AccountSummary(id: Self.account, provider: .openai, label: "OpenAI", mode: .anchored,
                                 capabilities: SpendTests.withCost)
    let inputs = SummaryInputs(
      accounts: [],
      usageDays: [
        UsageDay(accountId: Self.account, day: "2026-11-08", source: "provider", estCents: 999),
        UsageDay(accountId: Self.account, day: "2026-11-09", source: "provider", estCents: 200),
        UsageDay(accountId: Self.account, day: "2026-11-10", source: "provider", estCents: 50)
      ],
      costDays: [CostDay(accountId: Self.account, day: "2026-11-09", amountCents: 210)],
      anchorDayUsage: [UsageDay(accountId: Self.account, day: "2026-11-08", source: "provider", estCents: 40),
                       UsageDay(accountId: Self.account, day: "2026-11-08", source: "harness", estCents: 7)]
    )
    let anchor = Self.event("anchor", 10_000, "2026-11-08T12:00:00.000Z")
    let figure = Spend.sinceAnchor(summary, anchor: anchor, today: "2026-11-10", inputs: inputs)
    // 11-09: cost 210; 11-10: estimate 50; anchor day remainder 40 (harness ignored with a usage API).
    #expect(figure == SpendFigure(cents: 300, isEstimate: true))
  }

  // MARK: - End to end

  @Test("an anchored account after a usage poll: remaining, M, Day-1 runway, unknown band; anchor age; spend only")
  func builderEndToEnd() async throws {
    let harness = try await OpenAIHarness()
    let lifecycle = AccountLifecycle(repository: harness.repository, keyStore: harness.keys,
                                     registry: ProviderRegistry(adapters: [harness.adapter]),
                                     transport: harness.transport, logPipeline: harness.store.pipeline,
                                     now: harness.date.provider)
    try await lifecycle.setAnchor(OpenAIHarness.account, cents: 10_000,
                                  asOf: OpenAIHarness.now.addingTimeInterval(-40 * 86_400), note: "  billing page  ")
    await harness.on(OpenAIHarness.usage, "usage_completions.ok", "usage_completions.page2")
    #expect(await harness.run(.usage) == .succeeded(rows: 4))
    var stream = harness.repository.observeSummaryInputs().makeAsyncIterator()
    let inputs = try #require(await stream.next())
    #expect(inputs.ledgerEvents.first?.note == "billing page")
    let context = AccountSummaryBuilder.SpendContext(range: .sevenDays, now: OpenAIHarness.now,
                                                    pricer: await harness.prices.pricer)
    let summary = try #require(AccountSummaryBuilder.summaries(from: inputs, spend: context).first)
    // Spend since the anchor: 1 cent (fixture usage, estimates only).
    #expect(summary.remainingCents == 9_999)
    // M = ceil(1 × 3 %) = 1, × 1.5 for a 40-day-old anchor (30-day steps) = ceil(1.5) = 2.
    #expect(summary.estimateBandCents == 2)
    #expect(summary.anchorAgeDays == 40)
    #expect(summary.burn7dCents == nil)
    #expect(summary.runwayMin == nil)
    #expect(summary.band == .unknown)
    #expect(summary.dollarFloorCents == 500)
    #expect(!summary.needsAnchor)

    var record = OpenAIHarness.account
    record.balanceMode = "spend_only"
    let spendOnly = AccountSummaryBuilder.summaries(from: SummaryInputs(accounts: [record],
                                                                        pollStates: inputs.pollStates),
                                                    spend: context).first
    #expect(spendOnly?.remainingCents == nil)
    #expect(spendOnly?.spend30dCents == 0)
  }

  @Test("auto-reload from the account row; reload pending at or below the threshold")
  func autoReload() {
    var record = OpenAIHarness.account
    record.autoReloadEnabled = true
    record.autoReloadBelowCents = 20_000
    record.autoReloadToCents = 5_000
    let poll = PollStateSummary(accountId: record.id, job: "usage", lastSuccessAt: "2026-11-10T11:00:00.000Z")
    let inputs = SummaryInputs(accounts: [record], pollStates: [poll],
                               ledgerEvents: [Self.event("anchor", 10_000, "2026-11-10T00:00:00.000Z")].map {
                                 var event = $0
                                 event.accountId = record.id
                                 return event
                               })
    let summary = AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: OpenAIHarness.now)).first
    #expect(summary?.autoReload == AutoReload(belowCents: 20_000, toCents: 5_000))
    #expect(summary?.reloadPending == true)
    #expect(summary?.band == .watch)
  }
}

/// The popover's rows, banner and the Overview totals (08; `Presentation/AccountPresentation.swift`).
@Suite struct AccountPresentationTests {
  @Test("pinned metric in row 2, the others in row 3; a missing pinned value yields its place")
  func cardRows() {
    let values: [CardRows.Metric: String] = [.runway: "~9 d", .remaining: "≈ $42 ± 3", .todaySpend: "today $1"]
    #expect(CardRows.rows(pinned: .runway, values: values) == ("~9 d", ["≈ $42 ± 3", "today $1"]))
    #expect(CardRows.rows(pinned: .todaySpend, values: values) == ("today $1", ["~9 d", "≈ $42 ± 3"]))
    #expect(CardRows.rows(pinned: .runway, values: [.remaining: "$5"]) == ("$5", []))
    #expect(CardRows.rows(pinned: .remaining, values: [:]) == (nil, []))
  }

  static func account(_ provider: ProviderID, band: Band, runway: TimeInterval? = nil, mode: BalanceMode = .anchored,
                      anchored: Bool = true, remaining: Int64? = nil, currency: Currency = .usd) -> AccountSummary {
    var summary = AccountSummary(id: provider.rawValue, provider: provider, label: provider.rawValue, mode: mode,
                                 currency: currency, remainingCents: remaining, estimateBandCents: remaining.map { _ in 3 },
                                 runwayMin: runway, band: band)
    summary.anchorAt = anchored ? Date(timeIntervalSince1970: 0) : nil
    return summary
  }

  @Test("banner: critical before low before a missing anchor; nothing when all is well")
  func banner() {
    let low = Self.account(.xai, band: .low, runway: 3 * 86_400)
    let critical = Self.account(.deepseek, band: .critical, runway: 3_600)
    let noAnchor = Self.account(.openai, band: .unknown, anchored: false)
    #expect(AlertBannerPick.pick([noAnchor, low, critical])?.kind == .runway("1 h"))
    #expect(AlertBannerPick.pick([noAnchor, low])?.account.provider == .xai)
    #expect(AlertBannerPick.pick([noAnchor])?.kind == .setAnchor)
    #expect(AlertBannerPick.pick([Self.account(.openai, band: .healthy)]) == nil)
    #expect(AlertBannerPick.pick([Self.account(.openai, band: .critical)])?.kind == .runway("< 1 h"))
  }

  @Test("banner text is at most 60 characters")
  func bannerFit() {
    #expect(AlertBannerPick.fit(label: "OpenAI", rest: ": ~1 d left") == "OpenAI: ~1 d left")
    let long = AlertBannerPick.fit(label: String(repeating: "x", count: 80), rest: ": set an anchor to see runway")
    #expect(long.count == 60)
    #expect(long.hasSuffix("\u{2026}: set an anchor to see runway"))
  }

  @Test("Overview: the shortest known runway; USD totals with + N non-USD")
  func overview() {
    let accounts = [
      Self.account(.openai, band: .healthy, runway: 20 * 86_400, remaining: 10_000),
      Self.account(.anthropic, band: .low, runway: 3 * 86_400, remaining: -200),
      Self.account(.xai, band: .unknown, runway: 86_400),
      Self.account(.deepseek, band: .healthy, runway: 86_400 / 2, remaining: 5_000, currency: .cny)
    ]
    #expect(OverviewTotals.shortest(accounts)?.provider == .deepseek)
    let total = OverviewTotals.remaining(accounts)
    #expect(total.cents == 10_000)
    #expect(total.bandCents == 6)
    #expect(total.usdAccounts == 2)
    #expect(total.nonUSD == 1)
    #expect(OverviewTotals.shortest([Self.account(.xai, band: .unknown, runway: 1)]) == nil)
  }
}
