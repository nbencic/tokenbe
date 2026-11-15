import Foundation

/// 05 § Remaining (14 § Stage 5.3 step 1): the direct balance, or `anchor + top-ups since − spend since anchor`.
public enum Remaining {
  /// The account's latest anchor (`ledger_event.kind = 'anchor'`, newest `ts`).
  public static func anchor(accountID: String, events: [LedgerEventRecord]) -> LedgerEventRecord? {
    events.filter { $0.accountId == accountID && $0.kind == "anchor" && $0.amountCents != nil }
      .max { ($0.ts, $0.id) < ($1.ts, $1.id) }
  }

  /// Σ top-ups strictly after the anchor.
  public static func topUps(accountID: String, after anchor: LedgerEventRecord, events: [LedgerEventRecord]) -> Int64 {
    events.filter { $0.accountId == accountID && $0.kind == "topup" && $0.ts > anchor.ts }
      .reduce(0) { $0 + ($1.amountCents ?? 0) }
  }

  /// The latest balance reading's snapshot in the account's currency (05 § Remaining "first currency entry": the
  /// probe made that entry's currency the account's, 02). A reading lists each currency once and shares one `ts`,
  /// so the currency, not the order, picks the row (Q-045). Nil when the latest reading has no such entry.
  public static func balance(accountID: String, currency: Currency, inputs: SummaryInputs) -> BalanceSnapshotRecord? {
    inputs.balances.filter { $0.accountId == accountID && $0.currency == currency.rawValue }.max { $0.ts < $1.ts }
  }

  /// D-deepseek-unavailable: the provider's latest reading says the account cannot be used (`is_available ==
  /// false`). The flag belongs to the whole reading, so any of its snapshots answers.
  public static func providerUnavailable(accountID: String, inputs: SummaryInputs) -> Bool {
    inputs.balances.filter { $0.accountId == accountID }.max { $0.ts < $1.ts }?.isAvailable == false
  }

  /// `direct`: the latest `balance_snapshot.amount_cents` in the account's currency (none yet → nil). `anchored`:
  /// `anchor + Σ topups − spend_since_anchor` (no anchor → nil). `spend_only`: nil.
  public static func cents(mode: BalanceMode, accountID: String, currency: Currency, inputs: SummaryInputs,
                           spendSinceAnchor: Int64?) -> Int64? {
    switch mode {
    case .direct:
      return balance(accountID: accountID, currency: currency, inputs: inputs)?.amountCents
    case .anchored:
      guard let anchor = anchor(accountID: accountID, events: inputs.ledgerEvents), let amount = anchor.amountCents,
            let spend = spendSinceAnchor else { return nil }
      return amount + topUps(accountID: accountID, after: anchor, events: inputs.ledgerEvents) - spend
    case .spendOnly:
      return nil
    }
  }
}
