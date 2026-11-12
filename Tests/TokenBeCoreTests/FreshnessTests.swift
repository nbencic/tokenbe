import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 4.2 Tests, `FreshnessTests`: 05's stale rule per primary job, the threshold's inputs (multiplier,
/// override, Low Power), the next flip, the Sources strip's statuses, the badges and the human messages.
@Suite struct FreshnessTests {
  static let now = Date(timeIntervalSince1970: 1_794_312_000)  // 2026-11-10T12:00:00Z

  /// An OpenAI (anchored, usage every 300 s) summary whose usage last succeeded `ago` seconds before `now`.
  static func openai(usageAgo ago: TimeInterval?, override: IntervalOverride = IntervalOverride()) -> AccountSummary {
    AccountSummary(id: "acct-openai", provider: .openai, label: "OpenAI", mode: .anchored,
                   freshness: [.usage: ago.map { now.addingTimeInterval(-$0) }],
                   capabilities: FixtureDBBuilder.capabilities, intervalOverride: override)
  }

  static let balanceOnly = Capabilities(usage: false, cost: false, balance: true, perKeyUsage: false, keyNames: false,
                                        balanceModeDefault: .direct, usageLag: .seconds(60), currencyHint: .cny)

  static func stale(_ summary: AccountSummary, _ context: FreshnessContext = FreshnessContext()) -> Bool {
    var summaries = [summary]
    Freshness.apply(to: &summaries, context: context, now: now)
    return summaries[0].isStale
  }

  @Test("the primary job: usage for anchored and spend-only accounts, balance for direct ones")
  func primaryJob() {
    #expect(Freshness.primaryJob(for: .anchored) == .usage)
    #expect(Freshness.primaryJob(for: .spendOnly) == .usage)
    #expect(Freshness.primaryJob(for: .direct) == .balance)
  }

  @Test("stale only past multiplier × interval: 3 × 300 s by default (05)")
  func threshold() {
    #expect(!Self.stale(Self.openai(usageAgo: 899)))
    #expect(!Self.stale(Self.openai(usageAgo: 900)), "exactly at the threshold is not past it")
    #expect(Self.stale(Self.openai(usageAgo: 901)))
    #expect(Self.stale(Self.openai(usageAgo: 601), FreshnessContext(staleMultiplier: 2)))
  }

  @Test("the threshold follows the interval the scheduler uses: setting, override, Low Power multiplier")
  func intervalInputs() {
    var settings = ScheduleSettings.defaults
    settings.usageIntervalOpenAIS = 60
    #expect(Self.stale(Self.openai(usageAgo: 181), FreshnessContext(settings: settings)))
    let override = IntervalOverride(seconds: [.usage: 600])
    #expect(!Self.stale(Self.openai(usageAgo: 1_799, override: override)))
    #expect(Self.stale(Self.openai(usageAgo: 1_801, override: override)))
    // Low Power ×4: 3 × 1200 s.
    #expect(!Self.stale(Self.openai(usageAgo: 3_599), FreshnessContext(lowPower: true)))
    #expect(Self.stale(Self.openai(usageAgo: 3_601), FreshnessContext(lowPower: true)))
  }

  @Test("never polled, unreadable capabilities, or a primary job the account lacks: not stale (Q-036)")
  func neverStale() {
    #expect(!Self.stale(Self.openai(usageAgo: nil)))
    var unreadable = Self.openai(usageAgo: 86_400)
    unreadable.capabilities = nil
    #expect(!Self.stale(unreadable))
    // An anchored account without a usage endpoint (02: xAI's anchored fallback) has no primary job to go stale.
    var noUsage = Self.openai(usageAgo: 86_400)
    noUsage.capabilities = Self.balanceOnly
    #expect(!Self.stale(noUsage))
    #expect(Freshness.staleAt(lastSuccess: Self.now, interval: nil, multiplier: 3) == nil)
  }

  @Test("a direct account goes stale on its balance job (60 s)")
  func directBalance() {
    let deepseek = AccountSummary(id: "acct-ds", provider: .deepseek, label: "DeepSeek", mode: .direct,
                                  freshness: [.balance: Self.now.addingTimeInterval(-181)],
                                  capabilities: Self.balanceOnly)
    #expect(Self.stale(deepseek))
  }

  @Test("apply returns the earliest instant an account turns stale, and sets each source's next run")
  func nextFlipAndNextDue() {
    var summaries = [
      Self.openai(usageAgo: 600),  // stale at now + 300
      AccountSummary(id: "acct-b", provider: .openai, label: "B", mode: .anchored,
                     freshness: [.usage: Self.now.addingTimeInterval(-100)],
                     capabilities: FixtureDBBuilder.capabilities),  // stale at now + 800
      Self.openai(usageAgo: 5_000)  // already stale: no flip ahead
    ]
    summaries[0].sources = SourceStatus.all(capabilities: FixtureDBBuilder.capabilities, states: [])
    let due = Self.now.addingTimeInterval(42)
    let next = Freshness.apply(to: &summaries, context: FreshnessContext(nextDue: ["acct-openai": [.usage: due]]),
                               now: Self.now)
    #expect(next == Self.now.addingTimeInterval(300))
    #expect(summaries.map(\.isStale) == [false, false, true])
    #expect(summaries[0].sources.first { $0.job == .usage }?.nextDue == due)
    #expect(summaries[0].sources.first { $0.job == .balance }?.nextDue == nil, "n/a has no next run")
    var none = [Self.openai(usageAgo: nil)]
    #expect(Freshness.apply(to: &none, context: FreshnessContext(), now: Self.now) == nil)
  }

  @Test("sources: ok, failed with its message, never, n/a; unreadable capabilities count as applying")
  func sources() {
    let states = [
      PollStateSummary(accountId: "a", job: "usage", lastSuccessAt: "2026-11-10T11:58:00.000Z"),
      PollStateSummary(accountId: "a", job: "keys", lastSuccessAt: "2026-11-10T11:00:00.000Z",
                       lastErrorClass: "server", lastErrorMessage: "OpenAI returned a server error (HTTP 500). Try again later."),
      PollStateSummary(accountId: "a", job: "cost")
    ]
    let all = SourceStatus.all(capabilities: FixtureDBBuilder.capabilities, states: states)
    #expect(all.map(\.job) == Job.allCases)
    #expect(all.map(\.state) == [.succeeded, .never, .notApplicable, .failed])
    #expect(all[0].lastSuccessAt == Date(timeIntervalSince1970: 1_794_311_880))
    #expect(all[3].message == "OpenAI returned a server error (HTTP 500). Try again later.")
    #expect(all[3].lastSuccessAt == Date(timeIntervalSince1970: 1_794_308_400), "the last success is kept")
    #expect(all[3].id == .keys)
    #expect(SourceStatus.all(capabilities: nil, states: []).map(\.state) == [.never, .never, .never, .never])
  }

  @Test("the builder fills capabilities, the clamped override and the sources from the rows")
  func builder() {
    var record = FixtureDBBuilder.account()
    record.intervalOverrideJson = #"{"usage":5}"#
    let inputs = SummaryInputs(accounts: [record], pollStates: [
      PollStateSummary(accountId: record.id, job: "usage", lastErrorClass: "transport", lastErrorMessage: "m")
    ])
    let summary = AccountSummaryBuilder.summaries(from: inputs)[0]
    #expect(summary.capabilities == FixtureDBBuilder.capabilities)
    #expect(summary.intervalOverride.seconds == [.usage: 60])
    #expect(summary.sources.first?.state == .failed && summary.sources.first?.message == "m")
    record.capabilities = "{"
    #expect(AccountSummaryBuilder.summaries(from: SummaryInputs(accounts: [record]))[0].capabilities == nil)
  }

  @Test("badges (08 B1-0): balance from the mode; usage, cost and lag from 02's capabilities")
  func badges() {
    let openai = AccountBadges(mode: .anchored, capabilities: FixtureDBBuilder.capabilities)
    #expect(openai == AccountBadges(mode: .anchored, capabilities: FixtureDBBuilder.capabilities))
    #expect(openai.balance == .anchored && openai.usage == .perKey && openai.cost == .provider)
    #expect(openai.lag == .seconds(3600))
    let deepseek = AccountBadges(mode: .direct, capabilities: Self.balanceOnly)
    #expect(deepseek.balance == .direct && deepseek.usage == .harness && deepseek.cost == .estimated)
    var orgOnly = FixtureDBBuilder.capabilities
    orgOnly.perKeyUsage = false
    let spend = AccountBadges(mode: .spendOnly, capabilities: orgOnly)
    #expect(spend.balance == .none && spend.usage == .orgOnly)
    #expect([AccountBadges.UsageSource.perKey, .orgOnly, .harness].map(\.rawValue) == ["per key", "org only", "harness"])
  }

  @Test("next run: now, seconds, whole minutes rounded up")
  func untilNextRun() {
    let now = Self.now
    #expect(Formatters.untilNextRun(now.addingTimeInterval(-5), now: now) == "now")
    #expect(Formatters.untilNextRun(now.addingTimeInterval(42.6), now: now) == "42 s")
    #expect(Formatters.untilNextRun(now.addingTimeInterval(121), now: now) == "3 min")
    #expect(Formatters.untilNextRun(now.addingTimeInterval(3_900), now: now) == "1 h 5 min")
  }

  @Test("human messages per failure class (02 probe messages; authored otherwise, Q-029, Q-036)")
  func humanMessages() {
    let openai = ProviderID.openai
    #expect(PollError.auth(http: 401, body: "x").humanMessage(provider: openai) == CoreStrings.OpenAI.notAdminKey)
    #expect(PollError.auth(http: 403, body: "x").humanMessage(provider: openai) == CoreStrings.OpenAI.missingScope)
    #expect(PollError.auth(http: 401, body: "x").humanMessage(provider: .anthropic)
            == "Anthropic answered with HTTP 401.")
    #expect(PollError.rateLimited(retryAfter: nil).humanMessage(provider: openai) == CoreStrings.rateLimited("OpenAI"))
    #expect(PollError.server(http: 503, body: "").humanMessage(provider: openai)
            == "OpenAI returned a server error (HTTP 503). Try again later.")
    #expect(PollError.transport(URLError(.notConnectedToInternet)).humanMessage(provider: openai)
            == CoreStrings.unreachable("OpenAI"))
    #expect(PollError.cancelled.humanMessage(provider: openai) == CoreStrings.unreachable("OpenAI"))
    #expect(PollError.providerRule("http 404").humanMessage(provider: openai) == "OpenAI answered with HTTP 404.")
    #expect(PollError.providerRule("openai_usage_more_than_50_pages").humanMessage(provider: openai)
            == CoreStrings.unexpectedResponse("OpenAI"))
    #expect(PollError.decode(field: "data", path: "$").humanMessage(provider: openai)
            == CoreStrings.unexpectedResponse("OpenAI"))
  }
}
