import SwiftUI
import TokenBeCore

/// 08 § Account detail (Paper `8T-0`), Stage 4.2's shell: the header (`AM-0`, `AR-0`), the badges row (`B1-0`) and
/// the sources strip (`HP-0`). The numbers strip and the tables arrive in 5.2/5.3, 7.1 and 8.1; the anchor and
/// top-up buttons arrive with their sheets in 5.3 (D6).
struct AccountDetailView: View {
  let model: AppModel
  let summary: AccountSummary

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        if let capabilities = summary.capabilities {
          BadgesRow(provider: summary.provider, badges: AccountBadges(mode: summary.mode, capabilities: capabilities))
        }
        SourcesStrip(sources: summary.sources)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(summary.label)
    .accessibilityIdentifier("dashboard.account")
  }

  /// Provider glyph, label, mode chip, band pill and freshness; `Refresh` on the right.
  private var header: some View {
    HStack(alignment: .top, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
          ProviderGlyph(provider: summary.provider, size: 24)
          Text(summary.label)
            .font(.title2.weight(.semibold))
            .accessibilityIdentifier("dashboard.account.label")
          if let chip = modeChip {
            Text(chip)
              .font(.body)
              .foregroundStyle(.secondary)
          }
          BandPill(band: summary.band)
        }
        TimelineView(.periodic(from: .now, by: 30)) { context in
          Text(Formatters.freshness(summary.lastSuccessAt, now: context.date, calendar: .current, stale: dimmed))
            .font(.callout.monospacedDigit())
            .foregroundStyle(dimmed ? Color(.healthLow) : Color.secondary)
            .accessibilityIdentifier("dashboard.account.freshness")
        }
      }
      Spacer()
      Button(Strings.refresh) { model.refreshNow(summary.id) }
        .padding(.top, 4)
        .accessibilityIdentifier("dashboard.account.refresh")
    }
  }

  /// Stale, or offline (08: offline puts every account under the stale overlay).
  private var dimmed: Bool { summary.isStale || model.isOffline }

  private var modeChip: String? {
    switch summary.mode {
    case .direct: nil
    case .anchored: Strings.modeAnchored
    case .spendOnly: Strings.modeSpendOnly
    }
  }
}

/// The band word on a tinted capsule (08 header `band pill`).
struct BandPill: View {
  let band: Band

  var body: some View {
    Text(band.word)
      .font(.caption.weight(.medium))
      .foregroundStyle(band.color)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(band.color.opacity(0.12), in: Capsule())
      .accessibilityLabel(Strings.bandLabel(band.word))
      .accessibilityIdentifier("dashboard.account.band")
  }
}
