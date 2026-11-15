import SwiftUI
import TokenBeCore

/// 08 § Overview. No placeholder headline (14 § 1.2): with no accounts it shows the real empty state and the
/// `Spend by day` card's empty text. With accounts: the headline and its sublines (5.2, 5.3) and the runway board
/// (5.3); the chart and tiles arrive with their data (8.2, 7.1).
struct OverviewView: View {
  let model: AppModel
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
        } else {
          let hideCents = model.environment?.settings.uiHideCents ?? true
          OverviewHeadline(accounts: model.accounts, hideCents: hideCents, totalSpend: totalSpend)
          RunwayBoard(model: model, hideCents: hideCents) { summary in
            anchorAccount = model.records.first { $0.id == summary.id }.map(AnchorTarget.init)
          }
        }
        spendByDay
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

  private var spendByDay: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(Strings.spendByDay)
        .font(.headline)
        .accessibilityIdentifier("dashboard.spendByDay.title")
      Text(Strings.noSpendInRange)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 160)
        .accessibilityIdentifier("dashboard.spendByDay.empty")
    }
    .padding(16)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.spendByDay")
  }
}

/// The runway board's `Set anchor…` target (a sheet needs an `Identifiable` item).
struct AnchorTarget: Identifiable {
  let record: AccountRecord
  var id: String { record.id }
}
