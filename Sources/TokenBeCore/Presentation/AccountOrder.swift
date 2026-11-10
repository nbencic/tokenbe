import Foundation

/// Card order in the popover (09 `tb.popover.sort`, `tb.popover.manualOrder`).
public enum AccountOrder {
  public enum Sort: String, CaseIterable, Sendable {
    case runway, remaining, name, manual
  }

  /// - `runway`: shortest runway first; unknown runways last.
  /// - `remaining`: lowest remaining first; unknown amounts last.
  /// - `name`: by label, case- and diacritic-insensitive.
  /// - `manual`: the providers in `manualOrder`, then every missing provider in name order (09).
  /// Ties fall back to name, then provider id, so the order is stable.
  public static func sorted(_ accounts: [AccountSummary], by sort: Sort, manualOrder: [String]) -> [AccountSummary] {
    switch sort {
    case .runway:
      return accounts.sorted { ascending($0.runwayMin, $1.runwayMin, $0, $1) }
    case .remaining:
      return accounts.sorted { ascending($0.remainingCents, $1.remainingCents, $0, $1) }
    case .name:
      return accounts.sorted(by: byName)
    case .manual:
      let rank = Dictionary(manualOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
      return accounts.sorted { lhs, rhs in
        switch (rank[lhs.provider.rawValue], rank[rhs.provider.rawValue]) {
        case let (left?, right?): left < right
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): byName(lhs, rhs)
        }
      }
    }
  }

  /// Known values ascending, unknown last, ties by name.
  private static func ascending<Value: Comparable>(
    _ left: Value?, _ right: Value?, _ lhs: AccountSummary, _ rhs: AccountSummary
  ) -> Bool {
    switch (left, right) {
    case let (left?, right?) where left != right: left < right
    case (.some, nil): true
    case (nil, .some): false
    default: byName(lhs, rhs)
    }
  }

  private static func byName(_ lhs: AccountSummary, _ rhs: AccountSummary) -> Bool {
    let order = lhs.label.compare(rhs.label, options: [.caseInsensitive, .diacriticInsensitive])
    if order != .orderedSame { return order == .orderedAscending }
    return lhs.provider.rawValue < rhs.provider.rawValue
  }
}
