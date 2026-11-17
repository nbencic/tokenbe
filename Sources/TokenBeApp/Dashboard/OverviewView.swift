import SwiftUI
import TokenBeCore

/// 08 § Overview. No placeholder headline (14 § 1.2): with no accounts it shows the real empty state and the
/// `Spend by day` card's empty text. With accounts: the headline and its sublines (5.2, 5.3) and the runway board
/// (5.3); the `Spend by day` chart (8.2); `Apps this period` (7.1); the cache savings tile (8.2), in 08's order.
struct OverviewView: View {
  let model: AppModel
  /// An `Apps this period` row was clicked (7.3: the Dashboard opens its account page filtered by the app).
  var openApp: (AppTotal) -> Void = { _ in }
  @State private var anchorAccount: AnchorTarget?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if model.accounts.isEmpty {
          VStack(spacing: 6) {
            Text(Strings.emptyHeadline)
              .font(.title3.weight(.semibold))
              .accessibilityIdentifier("dashboard.overview.empty.headline")
            Text(Strings.emptyBody)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("dashboard.overview.empty.body")
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 24)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("dashboard.overview.empty")
          SpendByDayChart(accounts: [], hideCents: true)
        } else {
          let hideCents = model.environment?.settings.uiHideCents ?? true
          OverviewHeadline(accounts: model.accounts, hideCents: hideCents, totalSpend: totalSpend)
          RunwayBoard(model: model, hideCents: hideCents) { summary in
            anchorAccount = model.records.first { $0.id == summary.id }.map(AnchorTarget.init)
          }
          SpendByDayChart(accounts: model.accounts, hideCents: hideCents)
          AppsThisPeriod(accounts: model.accounts, hideCents: hideCents) { openApp($0) }
          CacheTile(accounts: model.accounts, hideCents: hideCents)
        }
      }
      .padding(20)
    }
    .navigationTitle(Strings.overview)
    .accessibilityIdentifier("dashboard.overview")
    .sheet(item: $anchorAccount) { target in
      SetAnchorSheet(account: target.record, lifecycle: model.environment?.lifecycle)
    }
  }

  /// `Total spend 7 d ≈ $12.40 + 1 non-USD`, over the Dashboard range.
  private var totalSpend: String {
    let settings = model.environment?.settings
    let range = DashboardRange(setting: settings?.uiDashboardRange ?? DashboardRange.default.rawValue)
    let total = Spend.totalUSD(model.accounts)
    let amount = Formatters.spend(total.spend, currency: .usd, hideCents: settings?.uiHideCents ?? true,
                                  locale: .current)
    return Strings.totalSpend(range: RangePicker.label(range), amount: amount, nonUSD: total.nonUSD)
  }
}

/// The runway board's `Set anchor…` target (a sheet needs an `Identifiable` item).
struct AnchorTarget: Identifiable {
  let record: AccountRecord
  var id: String { record.id }
}
