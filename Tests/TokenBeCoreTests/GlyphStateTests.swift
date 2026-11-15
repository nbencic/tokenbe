import Foundation
import Testing
@testable import TokenBeCore

/// 08 § Menu bar glyph, 09 `tb.menubar.metric` (11 `GlyphStateTests`, 14 § Stage 5.5): dashed > notched > solid,
/// the persisted bands before the first poll (04 step 8), and the compact metric text.
@Suite struct GlyphStateTests {
  static let polled = Date(timeIntervalSince1970: 1_794_312_000)

  static func account(_ id: String, _ band: Band, polled: Bool = true, stale: Bool = false, runway: TimeInterval? = nil,
                      remaining: Int64? = nil, today: Int64? = nil, currency: Currency = .usd) -> AccountSummary {
    var summary = AccountSummary(id: id, provider: .openai, label: id, mode: .anchored, currency: currency,
                                 remainingCents: remaining, runwayMin: runway, band: band, isStale: stale)
    if polled { summary.freshness[.usage] = Self.polled }
    summary.todaySpend = today.map { SpendFigure(cents: $0, isEstimate: true) }
    return summary
  }

  static func band(_ id: String, _ band: Band) -> BandStateRecord {
    BandStateRecord(accountId: id, band: band.rawValue, since: "x", inputsJson: "{}")
  }

  @Test("dashed when offline or any account is stale; notched on any low or critical; else solid")
  func states() {
    let healthy = Self.account("a", .healthy)
    #expect(GlyphState.state(accounts: [healthy, Self.account("b", .watch)], offline: false, persisted: []) == .solid)
    #expect(GlyphState.state(accounts: [healthy, Self.account("b", .low)], offline: false, persisted: []) == .notched)
    #expect(GlyphState.state(accounts: [Self.account("b", .critical)], offline: false, persisted: []) == .notched)
    #expect(GlyphState.state(accounts: [Self.account("b", .critical)], offline: true, persisted: []) == .dashed)
    #expect(GlyphState.state(accounts: [Self.account("b", .low, stale: true)], offline: false, persisted: []) == .dashed)
    #expect(GlyphState.state(accounts: [Self.account("b", .unknown)], offline: false, persisted: []) == .solid)
    #expect(GlyphState.state(accounts: [], offline: false, persisted: []) == .solid)
  }

  @Test("startup step 8: before the first poll, the persisted band decides; after it, the computed band")
  func persisted() {
    let stored = [Self.band("a", .critical)]
    #expect(GlyphState.state(accounts: [], offline: false, persisted: stored) == .notched)
    #expect(GlyphState.state(accounts: [Self.account("a", .unknown, polled: false)], offline: false,
                             persisted: stored) == .notched)
    #expect(GlyphState.state(accounts: [Self.account("a", .healthy)], offline: false, persisted: stored) == .solid)
    #expect(GlyphState.state(accounts: [Self.account("z", .unknown, polled: false)], offline: false,
                             persisted: stored) == .solid)
  }

  @Test("metric text: 12d, 30h, <1h, >60d; lowest remaining; today's USD spend; none")
  func metric() {
    let posix = Locale(identifier: "en_US_POSIX")
    let accounts = [
      Self.account("a", .healthy, runway: 12.5 * 86_400, remaining: 4_217, today: 310),
      Self.account("b", .low, runway: 30 * 3_600, remaining: -50, today: 100),
      Self.account("c", .unknown, runway: 60, remaining: nil, today: 999, currency: .cny)
    ]
    #expect(MenuBarMetric.minRunway.text(accounts, hideCents: true, locale: posix) == "30h")
    #expect(MenuBarMetric.minRemaining.text(accounts, hideCents: true, locale: posix) == "$0")
    #expect(MenuBarMetric.todaySpend.text(accounts, hideCents: false, locale: posix) == "$4.10")
    #expect(MenuBarMetric.none.text(accounts, hideCents: true, locale: posix) == nil)
    #expect(MenuBarMetric.minRunway.text([Self.account("a", .healthy, runway: 12.5 * 86_400)], hideCents: true,
                                         locale: posix) == "12d")
    #expect(MenuBarMetric.compactRunway(600) == "<1h")
    #expect(MenuBarMetric.compactRunway(90 * 86_400) == ">60d")
    #expect(MenuBarMetric.minRunway.text([], hideCents: true, locale: posix) == nil)
    #expect(MenuBarMetric.minRemaining.text([], hideCents: true, locale: posix) == nil)
    #expect(MenuBarMetric.todaySpend.text([Self.account("c", .healthy, currency: .cny)], hideCents: true,
                                          locale: posix) == nil)
  }

  @Test("the band store returns every row for step 8")
  func fetchBandStates() async throws {
    let harness = try await OpenAIHarness()
    try await harness.repository.recordBand(Self.band(OpenAIHarness.account.id, .low))
    #expect(try await harness.repository.fetchBandStates().map(\.band) == ["low"])
  }
}
