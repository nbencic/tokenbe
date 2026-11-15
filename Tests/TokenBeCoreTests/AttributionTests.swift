import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 11 `AttributionTests`, the key path of 06 § Attribution precedence (14 § Stage 7.1): the By-app total equals the
/// provider total, the rounding remainder goes to the largest key, unbound keys are their own rows; the O-16 slug;
/// `Repository+Apps` on the real database. Split, substitute and inferred arrive in 7.2.
@Suite struct AttributionTests {
  static let account = "acct"
  static let today = "2026-11-10"
  static let days = ["2026-11-08", "2026-11-09", "2026-11-10"]
  static let perKey = Capabilities(usage: true, cost: true, balance: false, perKeyUsage: true, keyNames: true,
                                   balanceModeDefault: .anchored, usageLag: .seconds(3600), currencyHint: .usd)

  static func usage(_ day: String, _ key: String, est: Int64, tokens: Int64 = 1_000, requests: Int64 = 1,
                    source: String = "provider", account: String = account) -> KeyUsageDay {
    KeyUsageDay(accountId: account, day: day, providerKeyId: key, source: source, estCents: est,
                classes: TokenClasses(inputUncached: tokens, requests: requests))
  }

  /// 11-08: closed, per-key cost rows (a 300, b 100) under a total of 401 (1 ¢ without a key).
  /// 11-09: closed, only the total (90): split by the estimates 2 : 1.
  /// 11-10: open: the estimates (a 10, b 5, '' 1).
  static let inputs = SummaryInputs(
    accounts: [],
    usageDays: [
      UsageDay(accountId: account, day: "2026-11-08", source: "provider", estCents: 380),
      UsageDay(accountId: account, day: "2026-11-09", source: "provider", estCents: 30),
      UsageDay(accountId: account, day: "2026-11-10", source: "provider", estCents: 16),
      UsageDay(accountId: account, day: "2026-11-10", source: "harness", estCents: 500)
    ],
    costDays: [
      CostDay(accountId: account, day: "2026-11-08", amountCents: 401),
      CostDay(accountId: account, day: "2026-11-09", amountCents: 90)
    ],
    apps: [AppRecord(id: "app-1", name: "weather-collector", displayName: "Weather collector", createdAt: "",
                     isAuto: false),
           AppRecord(id: Attribution.unassignedID, name: "unassigned", displayName: "Unassigned", createdAt: "",
                     isAuto: true)],
    bindings: [AppBindingRecord(appId: "app-1", accountId: account, kind: "provider_key", value: "key_a")],
    providerKeys: [
      ProviderKeyRecord(accountId: account, providerKeyId: "key_a", name: "prod", redacted: "sk-...a9f2",
                        projectId: nil, workspaceId: nil, status: "active", firstSeenAt: "", lastSeenAt: ""),
      ProviderKeyRecord(accountId: account, providerKeyId: "key_b", name: nil, redacted: "sk-...c3d4",
                        projectId: nil, workspaceId: nil, status: "active", firstSeenAt: "", lastSeenAt: "")
    ],
    keyUsageDays: [
      usage("2026-11-08", "key_a", est: 280, tokens: 4_000, requests: 4),
      usage("2026-11-08", "key_b", est: 100),
      usage("2026-11-09", "key_a", est: 20),
      usage("2026-11-09", "key_b", est: 10),
      usage("2026-11-10", "key_a", est: 10),
      usage("2026-11-10", "key_b", est: 5),
      usage("2026-11-10", "", est: 1),
      usage("2026-11-10", "key_a", est: 500, source: "harness"),
      usage("2026-11-10", "key_a", est: 999, account: "other")
    ],
    keyCostDays: [
      KeyCostDay(accountId: account, day: "2026-11-08", providerKeyId: "key_a", amountCents: 300),
      KeyCostDay(accountId: account, day: "2026-11-08", providerKeyId: "key_b", amountCents: 100)
    ]
  )

  static func summary(_ capabilities: Capabilities? = perKey) -> AccountSummary {
    AccountSummary(id: account, provider: .openai, label: "OpenAI", mode: .anchored, capabilities: capabilities)
  }

  @Test("Σ rows == the provider total for the range; per-key cost, split total, estimates; remainder to the largest")
  func keyPathTotals() {
    let rows = Attribution.rows(Self.summary(), days: Self.days, today: Self.today, inputs: Self.inputs)
    let total = Spend.spend(Self.summary(), days: Self.days, today: Self.today, inputs: Self.inputs)
    #expect(total == SpendFigure(cents: 507, isEstimate: true))
    #expect(rows.reduce(0) { $0 + $1.spend.cents } == total.cents)
    // key_a: 300 + 1 (11-08's keyless cent, to the largest) + 60 (2/3 of 90) + 10 = 371; key_b: 100 + 30 + 5;
    // '': 1 on the open day. The harness row and the other account do not count.
    #expect(rows.map(\.providerKeyID) == ["key_a", "key_b", ""])
    #expect(rows.map(\.spend.cents) == [371, 135, 1])
    #expect(rows.allSatisfy { $0.spend.isEstimate }, "the open day is an estimate for every key that has one")
    #expect(rows.map(\.sharePercent) == [73, 27, 0])
    #expect(rows[0].tokens == TokenClasses(inputUncached: 6_000, requests: 6))
    #expect(rows.allSatisfy { $0.kind == .key })
  }

  @Test("bound keys carry the app; unbound keys their provider name and hint; keyless usage is Unassigned")
  func names() {
    let rows = Attribution.rows(Self.summary(), days: Self.days, today: Self.today, inputs: Self.inputs)
    #expect(rows[0].appID == "app-1" && rows[0].appName == "Weather collector")
    #expect(rows[0].keyName == "prod" && rows[0].keyHint == "a9f2")
    #expect(rows[1].appID == nil && rows[1].appName == nil && rows[1].keyName == nil && rows[1].keyHint == "c3d4")
    #expect(rows[2].appID == Attribution.unassignedID && rows[2].appName == "Unassigned" && rows[2].keyHint == nil)
    #expect(rows[0].id == "acct/key_a")
  }

  @Test("a closed day's total with no per-key estimates splits by tokens; with no usage at all it is Unassigned")
  func fallbacks() {
    let byTokens = Attribution.dayShares(
      figure: SpendFigure(cents: 100, isEstimate: false),
      usage: [Self.usage("d", "key_a", est: 0, tokens: 3), Self.usage("d", "key_b", est: 0, tokens: 1)], costs: [])
    #expect(byTokens == ["key_a": 75, "key_b": 25])
    let nothing = Attribution.dayShares(figure: SpendFigure(cents: 42, isEstimate: false), usage: [], costs: [])
    #expect(nothing == ["": 42])
    let noKeyCost = Attribution.dayShares(
      figure: SpendFigure(cents: 10, isEstimate: false), usage: [Self.usage("d", "key_a", est: 4)],
      costs: [KeyCostDay(accountId: "a", day: "d", providerKeyId: "key_a", amountCents: 7)])
    #expect(noKeyCost == ["key_a": 10], "what the per-key rows leave goes to the largest key")
  }

  @Test("the remainder rule: floors, then the rest to the largest weight (ties to the smallest key id)")
  func remainder() {
    #expect(Attribution.split(100, by: ["c": 1, "a": 1, "b": 1]) == ["a": 34, "b": 33, "c": 33])
    #expect(Attribution.split(10, by: ["a": 1, "b": 2]) == ["a": 3, "b": 7])
    #expect(Attribution.split(10, by: ["a": 0]) == [:])
    #expect(Attribution.largest([:]) == nil)
    #expect(Attribution.percent(1, of: 3) == 33 && Attribution.percent(1, of: 2) == 50
      && Attribution.percent(2, of: 3) == 67 && Attribution.percent(5, of: 0) == 0)
  }

  @Test("an account without per-key usage has no key rows (harness attribution is 7.2)")
  func noPerKey() {
    var deepseek = Self.perKey
    deepseek.perKeyUsage = false
    #expect(Attribution.rows(Self.summary(deepseek), days: Self.days, today: Self.today, inputs: Self.inputs).isEmpty)
    #expect(Attribution.rows(Self.summary(nil), days: Self.days, today: Self.today, inputs: Self.inputs).isEmpty)
  }

  @Test("popover row 4: up to 3 rows with spend; with more, two and `other` (Q-048)")
  func top() {
    func row(_ key: String, _ cents: Int64) -> AppRow {
      AppRow(accountID: "a", providerKeyID: key, appID: nil, appName: nil, keyName: key, keyHint: nil,
             tokens: TokenClasses(), spend: SpendFigure(cents: cents, isEstimate: true))
    }
    let three = Attribution.top([row("a", 5), row("b", 3), row("c", 1), row("z", 0)])
    #expect(three.rows.map(\.providerKeyID) == ["a", "b", "c"] && three.other == nil)
    let four = Attribution.top([row("a", 5), row("b", 3), row("c", 1), row("d", 2)])
    #expect(four.rows.map(\.providerKeyID) == ["a", "b"])
    #expect(four.other == SpendFigure(cents: 3, isEstimate: true))
  }

  @Test("Apps this period: one entry per app and currency across accounts, largest first, at most 8")
  func totals() {
    func row(_ account: String, _ key: String, app: String?, _ cents: Int64) -> AppRow {
      AppRow(accountID: account, providerKeyID: key, appID: app, appName: app, keyName: nil, keyHint: nil,
             tokens: TokenClasses(), spend: SpendFigure(cents: cents, isEstimate: false))
    }
    var openai = AccountSummary(id: "o", provider: .openai, label: "OpenAI", mode: .anchored)
    openai.byApp = [row("o", "k1", app: "weather", 300), row("o", "k2", app: nil, 50), row("o", "k3", app: nil, 0)]
    var other = AccountSummary(id: "x", provider: .xai, label: "xAI", mode: .anchored)
    other.byApp = [row("x", "k9", app: "weather", 200)]
    var cny = AccountSummary(id: "d", provider: .deepseek, label: "DeepSeek", mode: .direct, currency: .cny)
    cny.byApp = [row("d", "k5", app: "weather", 1_000)]
    let totals = Attribution.totals([openai, other, cny])
    #expect(totals.map(\.spend.cents) == [1_000, 500, 50])
    #expect(totals.map(\.currency) == [.cny, .usd, .usd])
    #expect(totals[1].row.appID == "weather" && totals[2].row.providerKeyID == "k2")
    var many = openai
    many.byApp = (1...12).map { row("o", "k\($0)", app: "app\($0)", Int64($0)) }
    #expect(Attribution.totals([many]).count == 8)
    #expect(Attribution.totals([many]).first?.spend.cents == 12)
  }

  @Test("O-16 slug: lowercase, `-` for other characters, repeats collapsed, trimmed, 64 max, `-2` on collision")
  func slug() {
    #expect(AppSlug.make("Weather Collector", taken: []) == "weather-collector")
    #expect(AppSlug.make("  --My   App!!  ", taken: []) == "my-app")
    #expect(AppSlug.make("svc.v2_beta", taken: []) == "svc.v2_beta")
    #expect(AppSlug.make("_.hidden", taken: []) == "hidden", "06's regex: the name starts with [a-z0-9]")
    #expect(AppSlug.make("Čitač", taken: []) == "ita", "O-16 maps every character outside [a-z0-9._-] to `-`")
    #expect(AppSlug.make("!!!", taken: []) == "app")
    #expect(AppSlug.make("", taken: ["app"]) == "app-2")
    #expect(AppSlug.make("Unassigned", taken: ["unassigned"]) == "unassigned-2")
    #expect(AppSlug.make("x", taken: ["x", "x-2"]) == "x-3")
    let long = String(repeating: "a", count: 70)
    #expect(AppSlug.make(long, taken: []).count == 64)
    let suffixed = AppSlug.make(long, taken: [String(repeating: "a", count: 64)])
    #expect(suffixed.count == 64 && suffixed.hasSuffix("a-2"))
    let dashed = String(repeating: "a", count: 61) + "-bb"
    #expect(AppSlug.make(dashed, taken: [dashed]) == String(repeating: "a", count: 61) + "-2",
            "the cut base does not end in `-` before the suffix")
    for name in ["weather-collector", "my-app", "svc.v2_beta", "app-2", suffixed] {
      #expect(name.range(of: "^[a-z0-9][a-z0-9._-]{0,63}$", options: .regularExpression) != nil, "\(name)")
    }
  }

  @Test("Repository+Apps: create and bind in one write, rename, rebind, unbind; the sentinel is never renamed")
  func repository() async throws {
    let harness = try StoreHarness()
    let repository = GRDBRepository(database: try await harness.open().database)
    let account = RepositoryAccountTests.openai
    try await repository.insertAccount(account)
    let key = ProviderKeyRef(accountID: account.id, providerKeyID: "key_a")
    let app = try await repository.upsertApp(displayName: "  Weather Collector ", binding: key)
    #expect(app.name == "weather-collector" && app.displayName == "Weather Collector" && !app.isAuto)
    #expect(try await repository.fetchBindings() == [
      AppBindingRecord(appId: app.id, accountId: account.id, kind: "provider_key", value: "key_a")
    ])
    let second = try await repository.upsertApp(displayName: "Weather collector", binding: nil)
    #expect(second.name == "weather-collector-2")
    try await repository.bind(appID: second.id, key: key)
    #expect(try await repository.fetchBindings().map(\.appId) == [second.id], "one binding per key")
    try await repository.upsertApp(id: app.id, displayName: "Forecasts")
    let apps = try await repository.fetchApps()
    #expect(apps.map(\.displayName) == ["Forecasts", "Unassigned", "Weather collector"])
    #expect(apps.first { $0.id == app.id }?.name == "weather-collector", "O-13: the name never changes")
    await #expect(throws: StoreError.notFound(Attribution.unassignedID)) {
      try await repository.upsertApp(id: Attribution.unassignedID, displayName: "Mine")
    }
    await #expect(throws: StoreError.notFound("nope")) { try await repository.upsertApp(id: "nope", displayName: "x") }
    try await repository.unbind(key: key)
    #expect(try await repository.fetchBindings().isEmpty)
    let unnamed = try await repository.upsertApp(displayName: "   ", binding: nil)
    #expect(unnamed.name == "app" && unnamed.displayName == "app", "03: the display name defaults to the name")
    try await repository.bind(appID: app.id, key: key)
    try await repository.deleteAccount(id: account.id)
    #expect(try await repository.fetchBindings().isEmpty, "bindings go with their account (cascade)")
    #expect(try await repository.fetchApps().count == 4, "apps outlive accounts (03: kept forever)")
  }

  @Test("the summary builder fills byApp and todayApps from observed fixture polls; Σ byApp == rangeSpend")
  func builderFromObservation() async throws {
    let harness = try await OpenAIHarness()
    await harness.on(OpenAIHarness.usage, "usage_completions.ok", "usage_completions.page2")
    #expect(await harness.run(.usage) == .succeeded(rows: 4))
    await harness.on(OpenAIHarness.costs, "costs.ok")
    #expect(await harness.run(.cost) != .failed("store"))
    _ = try await harness.repository.upsertApp(
      displayName: "Weather", binding: ProviderKeyRef(accountID: OpenAIHarness.account.id, providerKeyID: "key_fixture_a1b2"))
    try await harness.repository.upsertProviderKeys(accountID: OpenAIHarness.account.id, keys: [
      DiscoveredKey(providerKeyID: "key_fixture_c3d4", name: "batch", redacted: "sk-FIXTURE-openai-c3d4")
    ], seenAt: OpenAIHarness.now)
    var stream = harness.repository.observeSummaryInputs().makeAsyncIterator()
    let inputs = try #require(await stream.next())
    let context = AccountSummaryBuilder.SpendContext(range: .thirtyDays, now: OpenAIHarness.now,
                                                    pricer: await harness.prices.pricer)
    let summary = try #require(AccountSummaryBuilder.summaries(from: inputs, spend: context).first)
    let range = try #require(summary.rangeSpend)
    #expect(summary.byApp.reduce(0) { $0 + $1.spend.cents } == range.cents)
    #expect(Set(summary.byApp.map(\.providerKeyID)).isSuperset(of: ["key_fixture_a1b2", "key_fixture_c3d4"]))
    #expect(summary.byApp.first { $0.providerKeyID == "key_fixture_a1b2" }?.appName == "Weather")
    #expect(summary.byApp.first { $0.providerKeyID == "key_fixture_c3d4" }?.keyName == "batch")
    #expect(summary.todayApps.reduce(0) { $0 + $1.spend.cents } == summary.todaySpend?.cents)
  }
}
