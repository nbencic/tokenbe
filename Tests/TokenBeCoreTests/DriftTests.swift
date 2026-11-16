import Foundation
import Testing
@testable import TokenBeCore

/// 11 `DriftTests` (14 § Stage 8.1): 05 § Drift's line-item mapping, closed days only, `—` without a provider cost
/// row, the threshold, unpriced models (A6), the sources of the rows, the order, the builder, and the daily
/// `ledger.drift` check of yesterday.
@Suite struct DriftTests {
  static let account = "acct"
  static let today = "2026-11-10"
  static let days = ["2026-11-08", "2026-11-09", "2026-11-10"]
  static let openai = Capabilities(usage: true, cost: true, balance: false, perKeyUsage: true, keyNames: true,
                                   balanceModeDefault: .anchored, usageLag: .seconds(3600), currencyHint: .usd)

  static func usage(_ day: String, _ model: String, est: Int64, unpriced: Int64 = 0, tokens: Int64 = 1_000,
                    source: String = "provider", account: String = account) -> ModelUsageDay {
    ModelUsageDay(accountId: account, day: day, model: model, source: source, estCents: est,
                  unpricedBuckets: unpriced, classes: TokenClasses(inputUncached: tokens, output: tokens / 10,
                                                                   requests: 2))
  }

  static func cost(_ day: String, _ lineItem: String, _ cents: Int64, account: String = account) -> LineItemCostDay {
    LineItemCostDay(accountId: account, day: day, lineItem: lineItem, amountCents: cents)
  }

  static func summary(_ capabilities: Capabilities? = openai, currency: Currency = .usd) -> AccountSummary {
    AccountSummary(id: account, provider: .openai, label: "OpenAI", mode: .anchored, currency: currency,
                   capabilities: capabilities)
  }

  /// 11-08: mini est 100 vs cost 80 + 20 (two line items) → 0 %; 11-09: mini 150 vs 100 → +50 %; 4o 90 vs 100 →
  /// −10 %; 11-10 (open): mini 40 and a cost row that must not count.
  static var inputs: SummaryInputs {
    var inputs = SummaryInputs(accounts: [])
    inputs.modelUsageDays = [
      usage("2026-11-08", "gpt-4o-mini", est: 100),
      usage("2026-11-09", "gpt-4o-mini", est: 150),
      usage("2026-11-09", "gpt-4o", est: 90),
      usage("2026-11-10", "gpt-4o-mini", est: 40),
      usage("2026-11-10", "gpt-4o-mini", est: 999, source: "harness"),
      usage("2026-11-09", "gpt-4o-mini", est: 777, account: "other")
    ]
    inputs.lineItemCostDays = [
      cost("2026-11-08", "gpt-4o-mini, input", 80),
      cost("2026-11-08", "gpt-4o-mini, output", 20),
      cost("2026-11-09", "gpt-4o-mini, input", 100),
      cost("2026-11-09", "gpt-4o, input", 100),
      cost("2026-11-09", "web search tool calls", 7),
      cost("2026-11-10", "gpt-4o-mini, input", 5)
    ]
    return inputs
  }

  @Test("a line item maps to the longest model name it contains between boundaries; none → nil (Q-051)")
  func lineItemMapping() {
    let models = ["gpt-4o", "gpt-4o-mini", "gpt-4o-2024-08-06", ""]
    #expect(Drift.lineItemModel("gpt-4o-mini, input", models: models) == "gpt-4o-mini")
    #expect(Drift.lineItemModel("gpt-4o, cached input", models: models) == "gpt-4o")
    #expect(Drift.lineItemModel("gpt-4o-2024-08-06, output", models: models) == "gpt-4o-2024-08-06")
    #expect(Drift.lineItemModel("gpt-4o-mini", models: models) == "gpt-4o-mini", "no comma: the whole string")
    #expect(Drift.lineItemModel("Batch gpt-4o output", models: models) == "gpt-4o", "the name inside the text")
    #expect(Drift.lineItemModel("gpt-4o-minimal, input", models: ["gpt-4o-mini"]) == nil, "no partial names")
    #expect(Drift.lineItemModel("xgpt-4o, input", models: ["gpt-4o"]) == nil)
    #expect(Drift.lineItemModel("web search tool calls", models: models) == nil)
    #expect(Drift.lineItemModel("", models: models) == nil, "an empty model never matches")
  }

  @Test("rows: tokens and estimate over the range; provider cost and drift over closed days with a cost row")
  func rows() {
    let rows = Drift.rows(Self.summary(), days: Self.days, today: Self.today, inputs: Self.inputs, thresholdPct: 10)
    #expect(rows.map(\.model) == ["gpt-4o-mini", "gpt-4o"], "by estimate, largest first")
    let mini = rows[0]
    #expect(mini.estCents == 290, "100 + 150 + the open day's 40; the harness row and the other account do not count")
    #expect(mini.tokens == TokenClasses(inputUncached: 3_000, output: 300, requests: 6))
    #expect(mini.providerCents == 200, "the open day's cost row is left out")
    #expect(mini.drift == ModelDrift(days: 2, estCents: 250, providerCents: 200, basisPoints: 2_500, flagged: true))
    #expect(!mini.unpriced)
    let large = rows[1]
    #expect(large.providerCents == 100)
    #expect(large.drift == ModelDrift(days: 1, estCents: 90, providerCents: 100, basisPoints: -1_000, flagged: false),
            "exactly 10 % is not above the threshold")
    #expect(Drift.rows(Self.summary(), days: Self.days, today: Self.today, inputs: Self.inputs,
                       thresholdPct: 9)[1].drift?.flagged == true)
  }

  @Test("a closed day without a cost row for the model is not compared; no row at all is — (05)")
  func noCostRow() {
    var inputs = Self.inputs
    inputs.modelUsageDays.append(Self.usage("2026-11-08", "gpt-4o", est: 500))
    let rows = Drift.rows(Self.summary(), days: Self.days, today: Self.today, inputs: inputs, thresholdPct: 10)
    let large = rows.first { $0.model == "gpt-4o" }
    #expect(large?.estCents == 590 && large?.drift?.days == 1 && large?.drift?.estCents == 90,
            "11-08 has usage but no gpt-4o line item, so drift compares 11-09 only")
    inputs.modelUsageDays.append(Self.usage("2026-11-09", "o1", est: 30))
    let reasoning = Drift.rows(Self.summary(), days: Self.days, today: Self.today, inputs: inputs, thresholdPct: 10)
      .first { $0.model == "o1" }
    #expect(reasoning?.providerCents == nil && reasoning?.drift == nil && reasoning?.estCents == 30)
    let noCostAPI = Capabilities(usage: true, cost: false, balance: false, perKeyUsage: false, keyNames: false,
                                 balanceModeDefault: .anchored, usageLag: .seconds(60), currencyHint: .usd)
    #expect(Drift.rows(Self.summary(noCostAPI), days: Self.days, today: Self.today, inputs: Self.inputs,
                       thresholdPct: 10).allSatisfy { $0.providerCents == nil && $0.drift == nil },
            "an account without a cost API has no provider cost")
  }

  @Test("the open day alone has no drift; a provider cost of 0 is not divided by")
  func openDayAndZero() {
    #expect(Drift.rows(Self.summary(), days: [Self.today], today: Self.today, inputs: Self.inputs, thresholdPct: 10)
      .allSatisfy { $0.drift == nil && $0.providerCents == nil })
    var inputs = Self.inputs
    inputs.lineItemCostDays = [Self.cost("2026-11-09", "gpt-4o, input", 0)]
    let large = Drift.rows(Self.summary(), days: Self.days, today: Self.today, inputs: inputs, thresholdPct: 10)
      .first { $0.model == "gpt-4o" }
    #expect(large?.providerCents == 0 && large?.drift == nil)
  }

  @Test("an unpriced model is flagged in Est. cost, never $0, and never drifts, even with a cost row (A6, E2E-8)")
  func unpriced() {
    var inputs = Self.inputs
    inputs.modelUsageDays += [Self.usage("2026-11-09", "made-up-model-1", est: 0, unpriced: 3, tokens: 5_000),
                              Self.usage("2026-11-10", "made-up-model-1", est: 0, unpriced: 1)]
    inputs.lineItemCostDays.append(Self.cost("2026-11-09", "made-up-model-1, input", 400))
    let rows = Drift.rows(Self.summary(), days: Self.days, today: Self.today, inputs: inputs, thresholdPct: 10)
    #expect(rows.last?.model == "made-up-model-1", "unpriced models sort last")
    let row = rows.last
    #expect(row?.unpriced == true && row?.estCents == nil && row?.drift == nil)
    #expect(row?.providerCents == 400, "the provider's cost still shows")
    #expect(row?.tokens.inputUncached == 6_000)
    // One unpriced bucket among priced ones still makes the model's estimate unknown, not a partial sum.
    inputs.modelUsageDays.append(Self.usage("2026-11-08", "gpt-4o", est: 0, unpriced: 1))
    let large = Drift.rows(Self.summary(), days: Self.days, today: Self.today, inputs: inputs, thresholdPct: 10)
      .first { $0.model == "gpt-4o" }
    #expect(large?.estCents == nil && large?.drift == nil)
  }

  @Test("harness rows count only for a USD account without a usage API (Spend.counts)")
  func sources() {
    let harnessOnly = Capabilities(usage: false, cost: false, balance: true, perKeyUsage: false, keyNames: false,
                                   balanceModeDefault: .direct, usageLag: .seconds(300), currencyHint: .usd)
    var inputs = SummaryInputs(accounts: [])
    inputs.modelUsageDays = [Self.usage("2026-11-10", "deepseek-chat", est: 12, source: "harness")]
    let rows = Drift.rows(Self.summary(harnessOnly), days: Self.days, today: Self.today, inputs: inputs,
                          thresholdPct: 10)
    #expect(rows.map(\.model) == ["deepseek-chat"] && rows.first?.estCents == 12 && rows.first?.drift == nil)
    #expect(Drift.rows(Self.summary(harnessOnly, currency: .cny), days: Self.days, today: Self.today, inputs: inputs,
                       thresholdPct: 10).isEmpty, "a CN¥ account takes no USD harness estimate (Q-049)")
    #expect(Drift.rows(Self.summary(), days: Self.days, today: Self.today, inputs: inputs, thresholdPct: 10).isEmpty,
            "an account with a usage API ignores harness rows")
  }

  @Test("the builder fills byModel over the Dashboard range with SpendContext.driftThresholdPct")
  func builder() {
    let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00Z
    var inputs = Self.inputs
    inputs.accounts = [FixtureDBBuilder.account(id: Self.account)]
    inputs.pollStates = [PollStateSummary(accountId: Self.account, job: "usage", lastSuccessAt: "2026-11-10T11:59:00.000Z")]
    let summaries = AccountSummaryBuilder.summaries(from: inputs, spend: .init(range: .sevenDays, now: now,
                                                                               driftThresholdPct: 30))
    #expect(summaries.first?.byModel.map(\.model) == ["gpt-4o-mini", "gpt-4o"])
    #expect(summaries.first?.byModel.first?.drift?.flagged == false, "25 % is under a 30 % threshold")
    let today = AccountSummaryBuilder.summaries(from: inputs, spend: .init(range: .today, now: now))
    #expect(today.first?.byModel.map(\.model) == ["gpt-4o-mini"] && today.first?.byModel.first?.estCents == 40)
  }

  @Test("the daily step logs ledger.drift for yesterday's drifting models, once per model and day")
  func report() async throws {
    let harness = try StoreHarness()
    var inputs = Self.inputs
    inputs.accounts = [FixtureDBBuilder.account(id: Self.account)]
    let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10: yesterday is 11-09 (mini +50 %, 4o −10 %)
    let once = DailyOnce()
    let log = EventLog(pipeline: harness.pipeline)
    #expect(Drift.report(inputs, now: now, thresholdPct: 60, once: once, log: log).isEmpty)
    #expect(Drift.report(inputs, now: now, thresholdPct: 10, once: once, log: log) == ["acct/gpt-4o-mini"])
    #expect(Drift.report(inputs, now: now, thresholdPct: 10, once: once, log: log).isEmpty, "once per day")
    #expect(Drift.report(inputs, now: now, thresholdPct: 5, once: once, log: log) == ["acct/gpt-4o"])
    let records = await harness.records(.ledgerDrift)
    #expect(records.count == 2)
    let first = try #require(records.first)
    #expect(first.lvl == .warn && first.acct == "openai")
    #expect(first.ctx["model"] == "gpt-4o-mini" && first.ctx["drift_pct"] == 50.0)
    #expect(records.last?.ctx["drift_pct"] == -10.0)
    let tomorrow = now.addingTimeInterval(86_400)   // yesterday is 11-10: its cost row has no closed usage day pair
    #expect(Drift.report(inputs, now: tomorrow, thresholdPct: 5, once: once, log: log) == ["acct/gpt-4o-mini"],
            "11-10: est 40 vs cost 5")
  }
}
