import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 7.3 (Core parts of `DrilldownUITests`' paths): the drift chip's days, the `Unassigned` rows' element id,
/// the account an Apps-this-period entry opens, and the app filter (Q-050).
extension AttributionTests {
  static func appRow(_ account: String, _ key: String, app: String?, _ cents: Int64,
                     kind: AttributionKind = .key) -> AppRow {
    AppRow(accountID: account, providerKeyID: key, appID: app, appName: app, keyName: nil, keyHint: nil, kind: kind,
           tokens: TokenClasses(requests: 1), spend: SpendFigure(cents: cents, isEstimate: false))
  }

  @Test("drift chip: closed days of the range beyond the threshold, newest first; open day, top-up, anchored: none")
  func harnessDrifts() {
    var inputs = Self.deepseekInputs   // 11-09: harness 100, delta 110; 11-08: delta 100, no lines
    let days = ["2026-11-08", "2026-11-09", "2026-11-10"]
    #expect(Attribution.harnessDrifts(Self.deepseek(), days: days, today: "2026-11-10", inputs: inputs,
                                      thresholdPct: 5) == [HarnessDrift(day: "2026-11-09", harnessCents: 100,
                                                                        balanceCents: 110)])
    #expect(Attribution.harnessDrifts(Self.deepseek(), days: days, today: "2026-11-10", inputs: inputs,
                                      thresholdPct: 10).isEmpty, "10 ¢ of 110 is under 10 %")
    #expect(Attribution.harnessDrifts(Self.deepseek(), days: days, today: "2026-11-09", inputs: inputs,
                                      thresholdPct: 5).isEmpty, "the open day never drifts")
    inputs.harnessDays.append(Self.harness("2026-11-08", "weather", est: 10, account: "ds"))
    let both = Attribution.harnessDrifts(Self.deepseek(), days: days, today: "2026-11-10", inputs: inputs,
                                         thresholdPct: 5)
    #expect(both.map(\.day) == ["2026-11-09", "2026-11-08"] && both.last?.deltaCents == -90)
    inputs.ledgerEvents = [LedgerEventRecord(id: "t", accountId: "ds", ts: "2026-11-09T08:00:00.000Z", kind: "topup",
                                             amountCents: 500, currency: "USD", note: nil, source: "user")]
    #expect(Attribution.harnessDrifts(Self.deepseek(), days: days, today: "2026-11-10", inputs: inputs,
                                      thresholdPct: 5).map(\.day) == ["2026-11-08"], "a top-up day is not compared")
    var anchored = Self.deepseek()
    anchored.mode = .anchored
    #expect(Attribution.harnessDrifts(anchored, days: days, today: "2026-11-10", inputs: inputs,
                                      thresholdPct: 5).isEmpty)
  }

  @Test("the builder fills harnessDrift from SpendContext.driftThresholdPct")
  func builderDrift() {
    let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00Z
    var inputs = Self.deepseekInputs
    inputs.accounts = [FixtureDBBuilder.account(id: "ds", provider: "deepseek", label: "DeepSeek")]
    inputs.accounts[0].balanceMode = "direct"
    inputs.accounts[0].capabilities = #"{"balance":true,"balance_mode_default":"direct","cost":false,"currency_hint":"USD","key_names":false,"per_key_usage":false,"usage":false,"usage_lag_s":300}"#
    inputs.pollStates = [PollStateSummary(accountId: "ds", job: "balance", lastSuccessAt: "2026-11-10T11:59:00.000Z")]
    let strict = AccountSummaryBuilder.summaries(from: inputs, spend: .init(range: .sevenDays, now: now,
                                                                            driftThresholdPct: 5))
    #expect(strict.first?.harnessDrift.map(\.day) == ["2026-11-09"])
    let lenient = AccountSummaryBuilder.summaries(from: inputs, spend: .init(range: .sevenDays, now: now))
    #expect(lenient.first?.harnessDrift.isEmpty == true, "09's default threshold is 10 %")
  }

  @Test("Unassigned: keyless provider usage and a harness day without lines are the sentinel's rows, id `unassigned`")
  func unassigned() {
    var inputs = Self.deepseekInputs
    inputs.apps.append(AppRecord(id: Attribution.unassignedID, name: "unassigned", displayName: "Unassigned",
                                 createdAt: "", isAuto: true))
    // A harness bucket on 11-08 whose lines are gone (PM-7.2-1: raw lines purged before the buckets).
    inputs.usageDays.append(UsageDay(accountId: "ds", day: "2026-11-08", source: "harness", estCents: 25))
    let rows = Attribution.rows(Self.deepseek(), days: Self.days, today: Self.today, inputs: inputs)
    let orphan = rows.first { $0.appTag == nil }
    #expect(orphan?.appID == Attribution.unassignedID && orphan?.appName == "Unassigned")
    #expect(orphan?.kind == .harness && orphan?.spend.cents == 25 && orphan?.elementID == "unassigned")
    let keyless = Self.appRow("o", "", app: Attribution.unassignedID, 5)
    #expect(keyless.elementID == "unassigned" && keyless.appKey == Attribution.unassignedID)
    let unbound = Self.appRow("o", "k2", app: nil, 5)
    #expect(unbound.elementID == "k2" && unbound.appKey == "o/k2")
  }

  @Test("drilldown: the entry opens the account where the app spent most in its currency; ties to the first")
  func drilldown() throws {
    var openai = AccountSummary(id: "o", provider: .openai, label: "OpenAI", mode: .anchored)
    openai.byApp = [Self.appRow("o", "k1", app: "weather", 200), Self.appRow("o", "k2", app: nil, 50)]
    var xai = AccountSummary(id: "x", provider: .xai, label: "xAI", mode: .anchored)
    xai.byApp = [Self.appRow("x", "", app: "weather", 150, kind: .harness),
                 Self.appRow("x", "", app: "weather", 100, kind: .inferred)]
    var cny = AccountSummary(id: "d", provider: .deepseek, label: "DeepSeek", mode: .direct, currency: .cny)
    cny.byApp = [Self.appRow("d", "", app: "weather", 9_000, kind: .harness)]
    let accounts = [openai, xai, cny]
    let totals = Attribution.totals(accounts)
    let weather = try #require(totals.first { $0.row.appID == "weather" && $0.currency == .usd && $0.row.kind == .key })
    #expect(Attribution.drilldownAccount(weather, accounts: accounts) == "x", "every kind counts: 250 > 200")
    let yuan = try #require(totals.first { $0.currency == .cny })
    #expect(Attribution.drilldownAccount(yuan, accounts: accounts) == "d")
    let unbound = try #require(totals.first { $0.row.providerKeyID == "k2" })
    #expect(Attribution.drilldownAccount(unbound, accounts: accounts) == "o")
    xai.byApp[0].spend.cents = 100
    #expect(Attribution.drilldownAccount(weather, accounts: [openai, xai]) == "o", "a tie goes to the first account")
    #expect(Attribution.drilldownAccount(weather, accounts: [cny]) == nil)
  }

  @Test("filter: the rows of one app and their total; none in the range → no rows, no total")
  func filtered() {
    let rows = [Self.appRow("x", "", app: "weather", 150, kind: .harness),
                Self.appRow("x", "", app: "news", 40, kind: .harness),
                Self.appRow("x", "", app: "weather", 10, kind: .inferred)]
    let weather = Attribution.filtered(rows, appKey: "weather")
    #expect(weather.rows.count == 2 && weather.total?.spend.cents == 160 && weather.total?.tokens.requests == 2)
    let none = Attribution.filtered(rows, appKey: "gone")
    #expect(none.rows.isEmpty && none.total == nil)
  }
}
