import Foundation

/// Maps `SummaryInputs` to the `[AccountSummary]` the UI shows (04 I3: Core computes, the UI renders).
/// Stage 2.2 fills the identity fields: id, provider, label, balance mode and currency (14 § Stage 2.2); 3.5 adds
/// freshness, the circuit and `needsKey`.
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
  /// `missingKeys` holds the `keychain_ref`s startup step 3 found without a Keychain item (04): those accounts
  /// get `needsKey`, and their card reads `Key missing · Fix…` (08).
  public static func summaries(
    from inputs: SummaryInputs, missingKeys: Set<String> = [], skipped: (AccountRecord, InvalidRow) -> Void = { _, _ in }
  ) -> [AccountSummary] {
    let states = Dictionary(grouping: inputs.pollStates, by: \.accountId)
    return inputs.accounts.compactMap { record in
      switch summary(for: record) {
      case .success(var summary):
        apply(states[record.id] ?? [], to: &summary)
        summary.needsKey = missingKeys.contains(record.keychainRef)
        return summary
      case .failure(let invalid):
        skipped(record, invalid)
        return nil
      }
    }
  }

  /// Each job's last success (nil = never polled) and the latest open circuit.
  static func apply(_ states: [PollStateSummary], to summary: inout AccountSummary) {
    for state in states {
      guard let job = Job(rawValue: state.job) else { continue }
      summary.freshness[job] = state.lastSuccessAt.flatMap(DBTime.date)
    }
    summary.circuitOpenUntil = states.compactMap { $0.circuitOpenUntil.flatMap(DBTime.date) }.max()
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
