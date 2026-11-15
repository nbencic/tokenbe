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

  /// `direct`: the latest `balance_snapshot.amount_cents` (none yet → nil). `anchored`: `anchor + Σ topups −
  /// spend_since_anchor` (no anchor → nil). `spend_only`: nil.
  public static func cents(mode: BalanceMode, accountID: String, inputs: SummaryInputs,
                           spendSinceAnchor: Int64?) -> Int64? {
    switch mode {
    case .direct:
      return inputs.balances.filter { $0.accountId == accountID }.max { $0.ts < $1.ts }?.amountCents
    case .anchored:
      guard let anchor = anchor(accountID: accountID, events: inputs.ledgerEvents), let amount = anchor.amountCents,
            let spend = spendSinceAnchor else { return nil }
      return amount + topUps(accountID: accountID, after: anchor, events: inputs.ledgerEvents) - spend
    case .spendOnly:
      return nil
    }
  }
}
