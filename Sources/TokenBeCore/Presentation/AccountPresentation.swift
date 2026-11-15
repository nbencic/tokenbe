import Foundation

/// Which popover card value goes where (08 § Popover 3, 09 `tb.popover.pinnedMetric`): the pinned metric is row 2,
/// the other two move to row 3. A pinned metric with no value yet gives row 2 to the next one that has a value, so
/// Day-1 keeps the remaining amount large and reads `Collecting…` below it (08 § Popover states).
public enum CardRows {
  public enum Metric: String, CaseIterable, Sendable {
    case runway, remaining, todaySpend
  }

  /// `values` holds each metric's text, nil when it has none. Returns row 2 and row 3's parts, in metric order.
  public static func rows(pinned: Metric, values: [Metric: String]) -> (row2: String?, row3: [String]) {
    let order = [pinned] + Metric.allCases.filter { $0 != pinned }
    let present = order.compactMap { metric in values[metric].map { (metric, $0) } }
    guard let first = present.first else { return (nil, []) }
    return (first.1, present.dropFirst().map(\.1))
  }
}

/// The popover's alert banner (08 § Popover 2): one account, the worst first — `critical`, then `low`, then an
/// anchored account with no anchor (`unknown` because the anchor is missing). Ties keep the card order.
public enum AlertBannerPick {
  public enum Kind: Sendable, Equatable {
    /// `Anthropic: ~1 d left`
    case runway(String)
    /// `OpenAI: set an anchor to see runway`
    case setAnchor
  }

  public static func pick(_ accounts: [AccountSummary]) -> (account: AccountSummary, kind: Kind)? {
    for band in [Band.critical, .low] {
      if let account = accounts.first(where: { $0.band == band }) {
        let runway = Formatters.runway(account.runwayMin) ?? Formatters.runway(0) ?? ""
        return (account, .runway(runway))
      }
    }
    if let account = accounts.first(where: { $0.band == .unknown && $0.needsAnchor }) { return (account, .setAnchor) }
    return nil
  }

  /// 08: the banner line is at most 60 characters; a long label is shortened with `…`.
  public static func fit(label: String, rest: String, limit: Int = 60) -> String {
    let room = limit - rest.count
    guard label.count > room else { return label + rest }
    return String(label.prefix(max(1, room - 1))) + "\u{2026}" + rest
  }
}

/// The Overview headline (08 § Overview 1): the account with the shortest `runway_min`, and the USD total of
/// remaining with its band (05 § Currency: USD accounts only, `+ N non-USD`).
public enum OverviewTotals {
  public struct Remaining: Sendable, Equatable {
    public var cents: Int64
    public var bandCents: Int64
    /// USD accounts with a remaining amount.
    public var usdAccounts: Int
    public var nonUSD: Int
  }

  /// Shortest runway first; accounts without one are left out.
  public static func shortest(_ accounts: [AccountSummary]) -> AccountSummary? {
    accounts.filter { $0.runwayMin != nil && $0.band != .unknown }
      .min { ($0.runwayMin ?? 0, $0.label) < ($1.runwayMin ?? 0, $1.label) }
  }

  /// Σ remaining (negatives count as 0, like the cards) and Σ `M` over USD accounts that have a remaining amount.
  public static func remaining(_ accounts: [AccountSummary]) -> Remaining {
    let usd = accounts.filter { $0.currency == .usd && $0.remainingCents != nil }
    return Remaining(cents: usd.reduce(0) { $0 + max(0, $1.remainingCents ?? 0) },
                     bandCents: usd.reduce(0) { $0 + ($1.estimateBandCents ?? 0) },
                     usdAccounts: usd.count, nonUSD: accounts.filter { $0.currency != .usd }.count)
  }
}
