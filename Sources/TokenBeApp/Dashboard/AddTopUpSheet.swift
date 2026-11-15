import SwiftUI
import TokenBeCore

/// 08 § Add top-up sheet: Amount, Date (default now), Note. Saving inserts `ledger_event(kind=topup, source=user)`
/// and logs `ledger.topup` (Core `AccountLifecycle.addTopUp`).
struct AddTopUpSheet: View {
  let account: AccountRecord
  let lifecycle: AccountLifecycle?

  var body: some View {
    LedgerEntryForm(kind: .topUp, account: account) { cents, date, note in
      try await lifecycle?.addTopUp(account, cents: cents, asOf: date, note: note)
    }
  }
}
