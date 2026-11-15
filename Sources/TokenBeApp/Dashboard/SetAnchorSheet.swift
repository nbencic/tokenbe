import SwiftUI
import TokenBeCore

/// 08 § Set anchor sheet: Amount (the account's currency; required), As of (default now, never in the future),
/// Note (optional, 140 characters), the helper line, `Cancel` / `Set anchor`. Saving inserts
/// `ledger_event(kind=anchor, source=user)` and logs `ledger.anchor_set` (Core `AccountLifecycle.setAnchor`); the
/// numbers recompute from the database observation.
struct SetAnchorSheet: View {
  let account: AccountRecord
  let lifecycle: AccountLifecycle?

  var body: some View {
    LedgerEntryForm(kind: .anchor, account: account) { cents, date, note in
      try await lifecycle?.setAnchor(account, cents: cents, asOf: date, note: note)
    }
  }
}

/// The fields both ledger sheets share (08: amount, date, note).
struct LedgerEntryForm: View {
  enum Kind: String {
    case anchor, topUp
  }

  let kind: Kind
  let account: AccountRecord
  let save: (Int64, Date, String) async throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var amount = ""
  @State private var date = Date()
  @State private var note = ""
  @State private var failed = false
  @State private var saving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(kind == .anchor ? Strings.setAnchorButton : Strings.addTopUpButton)
        .font(.headline)
      Form {
        TextField(Strings.amount, text: $amount, prompt: Text(currencySymbol))
          .accessibilityIdentifier("ledger.sheet.amount")
        DatePicker(kind == .anchor ? Strings.asOf : Strings.date, selection: $date, in: ...Date(),
                   displayedComponents: [.date, .hourAndMinute])
          .accessibilityIdentifier("ledger.sheet.date")
        TextField(Strings.note, text: $note)
          .onChange(of: note) { _, value in
            if value.count > AccountLifecycle.noteLimit { note = String(value.prefix(AccountLifecycle.noteLimit)) }
          }
          .accessibilityIdentifier("ledger.sheet.note")
      }
      .formStyle(.grouped)
      if kind == .anchor {
        Text(Strings.anchorHelp)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if failed {
        Text(Strings.ledgerSaveFailed)
          .font(.caption)
          .foregroundStyle(Color(.healthLow))
          .accessibilityIdentifier("ledger.sheet.failed")
      }
      HStack {
        Spacer()
        Button(Strings.cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("ledger.sheet.cancel")
        Button(kind == .anchor ? Strings.setAnchorButton : Strings.addTopUpButton) { submit() }
          .keyboardShortcut(.defaultAction)
          .disabled(cents == nil || saving)
          .accessibilityIdentifier("ledger.sheet.save")
      }
    }
    .padding(20)
    .frame(width: 400)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("ledger.sheet.\(kind.rawValue)")
  }

  private var currencySymbol: String { (Currency(rawValue: account.currency) ?? .usd).symbol }

  /// Required, non-negative, in the account's currency (cents).
  private var cents: Int64? { Formatters.cents(fromInput: amount, locale: .current) }

  private func submit() {
    guard let cents else { return }
    saving = true
    let when = min(date, Date())
    Task {
      do {
        try await save(cents, when, note)
        dismiss()
      } catch {
        Log.error(.uiError, cat: .ui, msg: "ledger entry not saved", acct: account.provider, err: error,
                  ctx: ["view": .string(kind.rawValue)])
        failed = true
      }
      saving = false
    }
  }
}
