import Foundation

/// The menu-bar glyph's three shapes (08 § Menu bar glyph; 14 § Stage 5.5 step 1). Colour is never used in the menu
/// bar; the shape carries the state.
public enum GlyphState: String, CaseIterable, Sendable {
  /// All accounts healthy or watch (or nothing to report).
  case solid
  /// Any account low or critical.
  case notched
  /// Any account stale, or offline.
  case dashed

  /// `.dashed` if offline or any account is stale, else `.notched` if any band is `low`/`critical`, else `.solid`.
  /// An account without a poll yet uses its persisted `band_state` (04 startup step 8), so the glyph shows the last
  /// known state from launch until the first polls complete. Before the accounts are loaded, the persisted bands
  /// alone decide.
  public static func state(accounts: [AccountSummary], offline: Bool, persisted: [BandStateRecord]) -> GlyphState {
    if offline || accounts.contains(where: \.isStale) { return .dashed }
    let stored = Dictionary(persisted.map { ($0.accountId, Band(rawValue: $0.band) ?? .unknown) }) { first, _ in first }
    let bands = accounts.isEmpty
      ? Array(stored.values)
      : accounts.map { $0.lastSuccessAt == nil ? stored[$0.id] ?? $0.band : $0.band }
    return bands.contains { $0 == .low || $0 == .critical } ? .notched : .solid
  }
}

/// The optional text right of the glyph (09 `tb.menubar.metric`; 08: `12d`, `$42`, `$3.10`, at most 64 pt wide).
public enum MenuBarMetric: String, CaseIterable, Sendable {
  case none, minRunway, minRemaining, todaySpend

  /// - `minRunway`: the shortest `runway_min` among accounts not `unknown`, compact (`<1h`, `30h`, `12d`, `>60d`);
  /// - `minRemaining`: the lowest remaining (negatives as 0), in that account's currency;
  /// - `todaySpend`: today's spend summed over USD accounts (05 § Currency), with `≈` dropped for width.
  /// Nil when the metric is `none` or nothing is known yet.
  public func text(_ accounts: [AccountSummary], hideCents: Bool, locale: Locale) -> String? {
    switch self {
    case .none:
      return nil
    case .minRunway:
      return accounts.filter { $0.band != .unknown }.compactMap(\.runwayMin).min().map(Self.compactRunway)
    case .minRemaining:
      guard let lowest = accounts.filter({ $0.remainingCents != nil })
        .min(by: { ($0.remainingCents ?? 0) < ($1.remainingCents ?? 0) }), let cents = lowest.remainingCents else {
        return nil
      }
      return Formatters.remaining(Money(cents: cents, currency: lowest.currency), hideCents: hideCents, locale: locale)
    case .todaySpend:
      let usd = accounts.filter { $0.currency == .usd }.compactMap(\.todaySpend)
      guard !usd.isEmpty else { return nil }
      return Formatters.money(Money(cents: usd.reduce(0) { $0 + $1.cents }), hideCents: hideCents, locale: locale)
    }
  }

  /// 05's runway rule without spaces or `~`, for the menu bar: `<1h`, `N h` → `Nh`, `~N d` → `Nd`, `> 60 d` → `>60d`.
  static func compactRunway(_ seconds: TimeInterval) -> String {
    (Formatters.runway(seconds) ?? "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "~", with: "")
  }
}
