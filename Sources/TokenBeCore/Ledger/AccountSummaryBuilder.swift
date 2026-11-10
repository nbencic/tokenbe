import Foundation

/// Maps `SummaryInputs` to the `[AccountSummary]` the UI shows (04 I3: Core computes, the UI renders).
/// Stage 2.2 fills the identity fields only: id, provider, label, balance mode and currency (14 § Stage 2.2).
/// Later stages fill the rest from the inputs they add.
public enum AccountSummaryBuilder {
  /// A stored value the model has no case for. 03's CHECKs rule this out for `provider` and `balance_mode`;
  /// `currency` has no CHECK.
  public struct InvalidRow: Error, Sendable, Equatable, CustomStringConvertible {
    public let column: String
    public let value: String
    public var description: String { "unknown \(column) '\(value)'" }
  }

  /// One summary per account, in input order. A row that cannot be read is left out and reported to `skipped`,
  /// which the caller logs (`ui.error`), so one bad row never hides the other accounts.
  public static func summaries(
    from inputs: SummaryInputs, skipped: (AccountRecord, InvalidRow) -> Void = { _, _ in }
  ) -> [AccountSummary] {
    inputs.accounts.compactMap { record in
      switch summary(for: record) {
      case .success(let summary):
        return summary
      case .failure(let invalid):
        skipped(record, invalid)
        return nil
      }
    }
  }

  public static func summary(for record: AccountRecord) -> Result<AccountSummary, InvalidRow> {
    guard let provider = ProviderID(rawValue: record.provider) else {
      return .failure(InvalidRow(column: "provider", value: record.provider))
    }
    guard let mode = BalanceMode(rawValue: record.balanceMode) else {
      return .failure(InvalidRow(column: "balance_mode", value: record.balanceMode))
    }
    guard let currency = Currency(rawValue: record.currency) else {
      return .failure(InvalidRow(column: "currency", value: record.currency))
    }
    return .success(AccountSummary(id: record.id, provider: provider, label: record.label, mode: mode,
                                   currency: currency))
  }
}
