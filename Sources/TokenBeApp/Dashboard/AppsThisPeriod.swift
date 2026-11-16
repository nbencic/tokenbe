import SwiftUI
import TokenBeCore

/// 08 § Overview 4, **Apps this period**: the top 8 apps by spend over the Dashboard range across accounts, each with
/// its attribution badge (`key`, `≈ split`, `harness`, `inferred`). An app is summed per currency, never across
/// currencies (05). A row is a button: it opens the account page filtered by the app (14 § Stage 7.3).
struct AppsThisPeriod: View {
  let accounts: [AccountSummary]
  let hideCents: Bool
  var open: (AppTotal) -> Void = { _ in }

  var body: some View {
    let totals = Attribution.totals(accounts)
    if !totals.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(Strings.appsThisPeriod)
          .font(.headline)
        ForEach(totals) { total in
          Button { open(total) } label: {
            HStack(spacing: 8) {
              Text(Strings.appLabel(total.row))
              AttributionBadge(kind: total.row.kind)
              Spacer()
              Text(Formatters.spend(total.spend, currency: total.currency, hideCents: hideCents, locale: .current))
                .monospacedDigit()
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("dashboard.overview.apps.row.\(total.row.elementID).\(total.row.kind.rawValue)")
        }
      }
      .padding(16)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("dashboard.overview.apps")
    }
  }
}
