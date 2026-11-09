import SwiftUI

/// 08 § Overview. No placeholder headline (14 § 1.2): with no accounts it shows the real empty state and the
/// `Spend by day` card's empty text. The headline, runway board, chart and tiles arrive with their data.
struct OverviewView: View {
  let model: AppModel

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
        }
        spendByDay
      }
      .padding(20)
    }
    .navigationTitle(Strings.overview)
    .accessibilityIdentifier("dashboard.overview")
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
