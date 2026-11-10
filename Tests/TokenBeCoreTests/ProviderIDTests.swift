import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 3.3 Tests: the prefix validation table from 02, display names from 08, `Capabilities` JSON, and the
/// onboarding availability of `ProviderRegistry`. Key-shaped strings are built at runtime so no tracked file
/// contains one (`check-no-secrets.sh`).
@Suite struct ProviderIDTests {
  static func body(_ count: Int) -> String { String(repeating: "x", count: count) }

  @Test("prefix validation: 02 names a prefix for OpenAI and Anthropic only")
  func prefixes() {
    #expect(ProviderID.openai.keyPrefix == "sk-admin-")
    #expect(ProviderID.anthropic.keyPrefix == "sk-ant-admin01-")
    for provider in [ProviderID.openrouter, .deepseek, .xai] { #expect(provider.keyPrefix == nil) }

    struct Row {
      let provider: ProviderID
      let key: String
      let expected: KeyCheck
    }
    let table = [
      Row(provider: .openai, key: "sk-" + "admin-" + Self.body(40), expected: .plausible),
      Row(provider: .openai, key: "  sk-" + "admin-" + Self.body(40) + "\n", expected: .plausible),
      Row(provider: .openai, key: "sk-" + "proj-" + Self.body(40), expected: .wrongPrefix(expected: "sk-admin-")),
      Row(provider: .openai, key: "sk-" + Self.body(40), expected: .wrongPrefix(expected: "sk-admin-")),
      Row(provider: .openai, key: " \n", expected: .empty),
      Row(provider: .anthropic, key: "sk-" + "ant-admin01-" + Self.body(80), expected: .plausible),
      Row(provider: .anthropic, key: "sk-" + "ant-api03-" + Self.body(80),
          expected: .wrongPrefix(expected: "sk-ant-admin01-")),
      Row(provider: .anthropic, key: "", expected: .empty),
      Row(provider: .openrouter, key: "sk-" + "or-v1-" + Self.body(64), expected: .plausible),
      Row(provider: .deepseek, key: "sk-" + Self.body(32), expected: .plausible),
      Row(provider: .xai, key: "xai-" + Self.body(60), expected: .plausible),
      Row(provider: .xai, key: "anything", expected: .plausible),
      Row(provider: .deepseek, key: "\t", expected: .empty)
    ]
    for row in table {
      #expect(row.provider.checkKey(row.key) == row.expected, "\(row.provider) \(row.key.prefix(12))…")
    }
    #expect(ProviderID.normalizedKey("  abc \n") == "abc")
  }

  @Test("display names and order follow 08's onboarding tiles; raw values follow 03's CHECK")
  func names() {
    #expect(ProviderID.allCases.map(\.displayName) == ["OpenAI", "Anthropic", "OpenRouter", "DeepSeek", "xAI"])
    #expect(ProviderID.allCases.map(\.rawValue) == ["openai", "anthropic", "openrouter", "deepseek", "xai"])
  }
}

@Suite struct CapabilitiesTests {
  static let openai = Capabilities(usage: true, cost: true, balance: false, perKeyUsage: true, keyNames: true,
                                   balanceModeDefault: .anchored, usageLag: .seconds(3600), currencyHint: .usd)

  @Test("JSON shape is pinned: snake_case keys, lag in whole seconds, sorted")
  func shape() throws {
    #expect(try Self.openai.json() == #"{"balance":false,"balance_mode_default":"anchored","cost":true,"#
            + #""currency_hint":"USD","key_names":true,"per_key_usage":true,"usage":true,"usage_lag_s":3600}"#)
  }

  @Test("round trip, and every mode and currency decodes")
  func roundTrip() throws {
    for mode in BalanceMode.allCases {
      for currency in Currency.allCases {
        var value = Self.openai
        value.balanceModeDefault = mode
        value.currencyHint = currency
        value.usageLag = .seconds(300)
        #expect(try Capabilities.decode(json: value.json()) == value)
      }
    }
  }

  @Test("a stored row with a missing or unknown field fails to decode")
  func strict() {
    #expect(throws: (any Error).self) { try Capabilities.decode(json: #"{"usage":true}"#) }
    #expect(throws: (any Error).self) {
      try Capabilities.decode(json: #"{"balance":false,"balance_mode_default":"prepaid","cost":true,"currency_hint":"USD","key_names":true,"per_key_usage":true,"usage":true,"usage_lag_s":0}"#)
    }
  }

  @Test("the fixture DB's account row holds decodable Capabilities")
  func fixtureRow() throws {
    let record = FixtureDBBuilder.account()
    #expect(try Capabilities.decode(json: record.capabilities) == FixtureDBBuilder.capabilities)
  }
}

/// A minimal adapter for registry tests; it implements nothing beyond the probe.
struct TestAdapter: ProviderAdapter {
  let id: ProviderID

  func probe(key: String, transport: any HTTPTransport) async -> ProbeResult {
    ProbeResult(capabilities: CapabilitiesTests.openai, currency: .usd)
  }
}

@Suite struct ProviderRegistryTests {
  @Test("Release offers verified providers with an adapter; DEBUG offers every provider with an adapter; 08 order")
  func availability() {
    let adapters: Set<ProviderID> = [.xai, .openai, .deepseek]
    #expect(ProviderRegistry.available(isDebug: true, verified: [], adapters: adapters) == [.openai, .deepseek, .xai])
    #expect(ProviderRegistry.available(isDebug: false, verified: [], adapters: adapters) == [])
    #expect(ProviderRegistry.available(isDebug: false, verified: [.xai, .anthropic], adapters: adapters) == [.xai])
    #expect(ProviderRegistry.available(isDebug: true, verified: [.anthropic], adapters: []) == [])
    for verified in [Set<ProviderID>(), [.openai], Set(ProviderID.allCases)] {
      let release = ProviderRegistry.available(isDebug: false, verified: verified, adapters: Set(ProviderID.allCases))
      #expect(Set(release).isSubset(of: verified), "Release never offers an unverified provider (R13)")
    }
  }

  @Test("the registry keys adapters by provider and uses this build's verified set")
  func registry() async {
    let registry = ProviderRegistry(adapters: [TestAdapter(id: .deepseek), TestAdapter(id: .openai)])
    #expect(registry.verified == Verified.providers)
    #expect(registry.isDebug == ProviderRegistry.buildIsDebug)
    #expect(registry.adapter(for: .openai)?.id == .openai)
    #expect(registry.adapter(for: .xai) == nil)
    #expect(registry.availableForOnboarding == [.openai, .deepseek], "swift test runs DEBUG")
  }

  @Test("polls a provider does not offer answer providerRule (07 poll.provider_rule)")
  func unsupportedPolls() async throws {
    let adapter = TestAdapter(id: .deepseek)
    let context = PollContext(accountID: "acct", key: "k", cursor: nil, window: DateInterval(start: .now, duration: 60),
                              transport: StubTransport(), clock: ContinuousClock())
    await #expect(throws: PollError.providerRule("deepseek_no_usage_api")) { try await adapter.pollUsage(context) }
    await #expect(throws: PollError.providerRule("deepseek_no_cost_api")) { try await adapter.pollCost(context) }
    await #expect(throws: PollError.providerRule("deepseek_no_balance_api")) { try await adapter.pollBalance(context) }
    await #expect(throws: PollError.providerRule("deepseek_no_keys_api")) { try await adapter.pollKeys(context) }
    #expect(await adapter.probe(key: "k", transport: StubTransport()).currency == .usd)
  }
}
