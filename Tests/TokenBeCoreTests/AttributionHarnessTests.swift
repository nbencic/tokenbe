import Foundation
import Testing
@testable import TokenBeCore

/// 11 `AttributionTests`, the harness cases (14 § Stage 7.2 step 5; 06 § Attribution precedence): split (an OpenAI
/// key with 2 apps), substitute (DeepSeek), inferred (DeepSeek single app, no top-up), never-add; the drift check;
/// harness spend only in USD (Q-049); DeepSeek burn and anchored xAI spend from harness lines (PM-6.1-3, PM-6.2-2).
extension AttributionTests {
  static let noUsage = Capabilities(usage: false, cost: false, balance: true, perKeyUsage: false, keyNames: false,
                                    balanceModeDefault: .direct, usageLag: .seconds(300), currencyHint: .usd)

  static func harness(_ day: String, _ app: String, est: Int64, key: String = "", account: String = account,
                      lines: Int64 = 1) -> HarnessDay {
    HarnessDay(accountId: account, day: day, appTag: app, providerKeyId: key, estCents: est,
               classes: TokenClasses(inputUncached: 100 * lines, requests: lines))
  }

  static func app(_ tag: String) -> AppRecord {
    AppRecord(id: "app-\(tag)", name: tag, displayName: tag, createdAt: "", isAuto: true)
  }

  static func tag(_ tag: String, account: String = account) -> AppBindingRecord {
    AppBindingRecord(appId: "app-\(tag)", accountId: account, kind: "harness_tag", value: tag)
  }

  @Test("split: a key's day share goes to the harness apps that used the key, by their estimate; Σ unchanged")
  func split() {
    var inputs = Self.inputs
    inputs.apps += [Self.app("weather"), Self.app("news")]
    inputs.harnessDays = [Self.harness("2026-11-10", "weather", est: 30, key: "key_a"),
                          Self.harness("2026-11-10", "news", est: 10, key: "key_a")]
    let rows = Attribution.rows(Self.summary(), days: Self.days, today: Self.today, inputs: inputs)
    let total = Spend.spend(Self.summary(), days: Self.days, today: Self.today, inputs: inputs)
    #expect(rows.reduce(0) { $0 + $1.spend.cents } == total.cents, "never-add: the provider total is unchanged")
    let weather = rows.first { $0.appTag == "weather" }
    let news = rows.first { $0.appTag == "news" }
    // key_a's 11-10 share is 10 ¢ (its estimate), split 3 : 1 → 7 + 2 by floors, the 1 ¢ left to the larger.
    #expect(weather?.spend.cents == 8 && news?.spend.cents == 2)
    #expect(weather?.kind == .split && news?.kind == .split && weather?.providerKeyID == "key_a")
    #expect(weather?.appName == "weather" && weather?.elementID == "weather")
    #expect(rows.first { $0.providerKeyID == "key_a" && $0.kind == .key }?.spend.cents == 361,
            "key_a's other days stay key rows (371 − 10)")
    #expect(weather?.tokens.requests == 1, "a split row's tokens are its harness lines'")
  }

  static func deepseek(_ currency: Currency = .usd) -> AccountSummary {
    AccountSummary(id: "ds", provider: .deepseek, label: "DeepSeek", mode: .direct, currency: currency,
                   capabilities: noUsage)
  }

  /// Harness buckets of 100 ¢ on 11-09 (apps 60 : 40) and nothing on 11-08.
  static var deepseekInputs: SummaryInputs {
    var inputs = SummaryInputs(accounts: [], usageDays: [
      UsageDay(accountId: "ds", day: "2026-11-09", source: "harness", estCents: 100)
    ])
    inputs.apps = [app("weather"), app("news")]
    inputs.bindings = [tag("weather", account: "ds"), tag("news", account: "ds")]
    inputs.harnessDays = [harness("2026-11-09", "weather", est: 60, account: "ds"),
                          harness("2026-11-09", "news", est: 40, account: "ds")]
    inputs.balanceDays = [BalanceDay(accountId: "ds", day: "2026-11-07", currency: "USD", amountCents: 1_000),
                          BalanceDay(accountId: "ds", day: "2026-11-08", currency: "USD", amountCents: 900),
                          BalanceDay(accountId: "ds", day: "2026-11-09", currency: "USD", amountCents: 790)]
    return inputs
  }

  @Test("substitute: an account without a usage API takes its spend from harness lines, badge harness")
  func substitute() {
    let inputs = Self.deepseekInputs
    let rows = Attribution.rows(Self.deepseek(), days: Self.days, today: Self.today, inputs: inputs)
    #expect(rows.map(\.appTag) == ["weather", "news"] && rows.map(\.spend.cents) == [60, 40])
    #expect(rows.allSatisfy { $0.kind == .harness && $0.providerKeyID.isEmpty })
    #expect(Spend.spend(Self.deepseek(), days: Self.days, today: Self.today, inputs: inputs).cents == 100,
            "two apps: no inference, so 11-08 has no spend")
    #expect(Attribution.total(rows)?.spend.cents == 100)
  }

  @Test("substitute edge cases: a day with harness spend but no lines is Unassigned; zero estimates split by tokens")
  func substituteEdges() {
    var inputs = Self.deepseekInputs
    inputs.harnessDays = [Self.harness("2026-11-09", "weather", est: 0, account: "ds", lines: 3),
                          Self.harness("2026-11-09", "news", est: 0, account: "ds", lines: 1)]
    inputs.usageDays.append(UsageDay(accountId: "ds", day: "2026-11-10", source: "harness", estCents: 9))
    inputs.apps.append(AppRecord(id: Attribution.unassignedID, name: "unassigned", displayName: "Unassigned",
                                 createdAt: "", isAuto: true))
    let rows = Attribution.rows(Self.deepseek(), days: Self.days, today: Self.today, inputs: inputs)
    #expect(rows.first { $0.appTag == "weather" }?.spend.cents == 75)
    #expect(rows.first { $0.appTag == "news" }?.spend.cents == 25)
    let unassigned = rows.first { $0.appTag == nil }
    #expect(unassigned?.spend.cents == 9 && unassigned?.appID == Attribution.unassignedID && unassigned?.kind == .harness)
    #expect(rows.first { $0.appTag == "news" }?.id == "ds//news/harness")
  }

  @Test("inferred: one harness app, no lines and no top-up on a closed day → the balance delta, badge inferred")
  func inferred() {
    var inputs = Self.deepseekInputs
    inputs.bindings = [Self.tag("weather", account: "ds")]
    inputs.harnessDays.removeAll { $0.appTag == "news" }
    let days = Attribution.inferredDays(Self.deepseek(), today: Self.today, inputs: inputs)
    #expect(days == ["2026-11-08": 100], "11-09 has harness lines; 11-07 has no day before it")
    let rows = Attribution.rows(Self.deepseek(), days: Self.days, today: Self.today, inputs: inputs)
    #expect(rows.first { $0.kind == .inferred }?.spend.cents == 100)
    #expect(rows.first { $0.kind == .harness }?.spend.cents == 100)
    #expect(Spend.spend(Self.deepseek(), days: Self.days, today: Self.today, inputs: inputs).cents == 200)

    var topUp = inputs
    topUp.ledgerEvents = [LedgerEventRecord(id: "t", accountId: "ds", ts: "2026-11-08T09:00:00.000Z", kind: "topup",
                                            amountCents: 500, currency: "USD", note: nil, source: "user")]
    #expect(Attribution.inferredDays(Self.deepseek(), today: Self.today, inputs: topUp).isEmpty)
    var rising = inputs
    rising.balanceDays[1].amountCents = 1_200
    #expect(Attribution.inferredDays(Self.deepseek(), today: "2026-11-09", inputs: rising).isEmpty,
            "a balance that rose is no spend")
    #expect(Attribution.inferredDays(Self.deepseek(), today: "2026-11-08", inputs: inputs).isEmpty,
            "the open day is never inferred")
  }

  @Test("a CNY account counts no USD harness estimate (Q-049); its inferred delta is in CN¥")
  func cny() {
    var inputs = Self.deepseekInputs
    inputs.balanceDays = inputs.balanceDays.map { var day = $0; day.currency = "CNY"; return day }
    let account = Self.deepseek(.cny)
    #expect(Spend.spend(account, days: Self.days, today: Self.today, inputs: inputs).cents == 0)
    inputs.bindings = [Self.tag("weather", account: "ds")]
    inputs.harnessDays.removeAll { $0.appTag == "news" }
    #expect(Spend.spend(account, days: Self.days, today: Self.today, inputs: inputs).cents == 100)
    #expect(Attribution.harnessDrift(account, day: "2026-11-09", inputs: inputs, thresholdPct: 10) == nil)
  }

  @Test("drift: harness estimate against the balance delta, beyond tb.alerts.driftThresholdPct % of the delta")
  func drift() {
    let inputs = Self.deepseekInputs   // 11-09: harness 100, delta 110
    #expect(Attribution.harnessDrift(Self.deepseek(), day: "2026-11-09", inputs: inputs, thresholdPct: 10) == nil)
    #expect(Attribution.harnessDrift(Self.deepseek(), day: "2026-11-09", inputs: inputs, thresholdPct: 5) == -10)
    #expect(Attribution.harnessDrift(Self.deepseek(), day: "2026-11-08", inputs: inputs, thresholdPct: 5) == nil,
            "no harness lines that day")
  }

  @Test("the daily drift step logs ledger.harness_drift for yesterday's drifting accounts only")
  func reportDrift() async throws {
    let harness = try StoreHarness()
    var inputs = Self.deepseekInputs
    inputs.accounts = [FixtureDBBuilder.account(id: "ds", provider: "deepseek", label: "DeepSeek")]
    inputs.accounts[0].balanceMode = "direct"
    inputs.accounts[0].capabilities = #"{"balance":true,"balance_mode_default":"direct","cost":false,"currency_hint":"USD","key_names":false,"per_key_usage":false,"usage":false,"usage_lag_s":300}"#
    let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10: yesterday is 11-09 (harness 100, delta 110)
    #expect(Attribution.reportDrift(inputs, now: now, thresholdPct: 10, log: EventLog(pipeline: harness.pipeline)).isEmpty)
    #expect(Attribution.reportDrift(inputs, now: now, thresholdPct: 5, log: EventLog(pipeline: harness.pipeline)) == ["ds"])
    let record = try #require(await harness.records(.ledgerHarnessDrift).first)
    #expect(record.acct == "deepseek" && record.ctx["day"] == "2026-11-09" && record.ctx["delta_cents"] == -10)
  }

  @Test("DeepSeek burn and anchored xAI spend come from harness lines (PM-6.1-3, PM-6.2-2)")
  func burnFromHarness() {
    let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00Z
    let closed = (1...7).map { DailyOnce.utcDay(now.addingTimeInterval(Double(-86_400 * $0))) }
    var inputs = SummaryInputs(accounts: [
      FixtureDBBuilder.account(id: "ds", provider: "deepseek", label: "DeepSeek"),
      FixtureDBBuilder.account(id: "x", provider: "xai", label: "xAI")
    ])
    inputs.accounts[0].balanceMode = "direct"
    inputs.accounts[0].capabilities = #"{"balance":true,"balance_mode_default":"direct","cost":false,"currency_hint":"USD","key_names":false,"per_key_usage":false,"usage":false,"usage_lag_s":300}"#
    inputs.accounts[1].capabilities = #"{"balance":false,"balance_mode_default":"anchored","cost":false,"currency_hint":"USD","key_names":false,"per_key_usage":false,"usage":false,"usage_lag_s":60}"#
    inputs.pollStates = [PollStateSummary(accountId: "ds", job: "balance", lastSuccessAt: "2026-11-10T11:59:00.000Z")]
    for day in closed {
      inputs.usageDays += [UsageDay(accountId: "ds", day: day, source: "harness", estCents: 700),
                           UsageDay(accountId: "x", day: day, source: "harness", estCents: 70)]
      inputs.harnessDays += [Self.harness(day, "weather", est: 700, account: "ds"),
                             Self.harness(day, "weather", est: 70, account: "x")]
    }
    let summaries = AccountSummaryBuilder.summaries(from: inputs, spend: .init(range: .sevenDays, now: now))
    #expect(summaries.first { $0.id == "ds" }?.burn7dCents == 700)
    let xai = summaries.first { $0.id == "x" }
    #expect(xai?.hasHarness == true && xai?.burn7dCents == 70, "no polled job, harness spend all the same")
    #expect(xai?.byApp.first?.kind == .harness)
  }
}
