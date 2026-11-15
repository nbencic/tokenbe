import SwiftUI
import TokenBeCore

/// 08 § Overview 4, **Apps this period**: the top 8 apps by spend over the Dashboard range across accounts, each with
/// its attribution badge (7.1: `key`). An app is summed per currency, never across currencies (05). The row click
/// that opens the account page filtered by the app is 7.3's (14 § Stage 7.3); until then the rows are not buttons.
struct AppsThisPeriod: View {
  let accounts: [AccountSummary]
  let hideCents: Bool

  var body: some View {
    let totals = Attribution.totals(accounts)
    if !totals.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(Strings.appsThisPeriod)
          .font(.headline)
        ForEach(totals) { total in
          HStack(spacing: 8) {
            Text(Strings.appLabel(total.row))
            AttributionBadge(kind: total.row.kind)
            Spacer()
            Text(Formatters.spend(total.spend, currency: total.currency, hideCents: hideCents, locale: .current))
              .monospacedDigit()
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("dashboard.overview.apps.row")
        }
      }
      .padding(16)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("dashboard.overview.apps")
    }
  }
}
