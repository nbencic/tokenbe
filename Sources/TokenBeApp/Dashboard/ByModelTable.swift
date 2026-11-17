import SwiftUI
import TokenBeCore

/// 08 § Account detail 5, the **By model** table (Paper `G7-0`): Model | Requests | Input | Cache write | Cache read
/// | Output | Reasoning | Est. cost | Provider cost | Drift, over the Dashboard range (14 § Stage 8.1). Core computes
/// every figure (`Drift.rows`, 04 I3). A model the price book cannot price reads `unpriced` in Est. cost (A6) and
/// has no drift; Provider cost and Drift read `—` without a provider cost row (05). A drift beyond
/// `tb.alerts.driftThresholdPct` is flagged in `HealthWatch` with an icon, and its label says so (08 §
/// Accessibility). The help names the estimate and the provider's cost over the days drift compares (Q-051).
struct ByModelTable: View {
  let rows: [ModelRow]
  let currency: Currency
  let hideCents: Bool
  let thresholdPct: Int
  /// The row with keyboard focus (08 § Accessibility, `TableKeyboard`).
  @FocusState private var focusedRow: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(Strings.byModel)
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        GridRow(alignment: .bottom) {
          Text(Strings.columnModel).font(.caption).foregroundStyle(.secondary)
          ForEach([Strings.columnRequests, Strings.columnInput, Strings.columnCacheWrite, Strings.columnCacheRead,
                   Strings.columnOutput, Strings.columnReasoning, Strings.columnEstCost, Strings.columnProviderCost,
                   Strings.columnDrift], id: \.self) { title in
            // Two-word titles take two lines, so ten columns leave the model name room at 920 pt (08).
            Text(title.replacingOccurrences(of: " ", with: "\n"))
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.trailing)
              .fixedSize()
              .accessibilityLabel(title)
              .gridColumnAlignment(.trailing)
          }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
        ForEach(rows) { row in
          GridRow {
            Text(row.model)
              .lineLimit(1)
              .truncationMode(.middle)
              .help(row.model)
              .tableRowFocus(row.model, $focusedRow)
              .accessibilityIdentifier("dashboard.account.byModel.model.\(row.model)")
            count(row.tokens.requests)
            count(row.tokens.inputUncached)
            count(row.tokens.cacheWrite5m + row.tokens.cacheWrite1h)
            count(row.tokens.cacheRead)
            count(row.tokens.output)
            count(row.tokens.reasoning)
            estimate(row)
            provider(row)
            drift(row)
          }
        }
      }
    }
    .padding(16)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .tableKeyboard(rows.map(\.model), $focusedRow)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.account.byModel")
  }

  private func count(_ value: Int64) -> some View {
    Text(Formatters.tokens(value, locale: .current)).monospacedDigit().fixedSize()
  }

  @ViewBuilder private func estimate(_ row: ModelRow) -> some View {
    if let cents = row.estCents {
      Text(Formatters.spend(SpendFigure(cents: cents, isEstimate: true), currency: currency, hideCents: hideCents,
                            locale: .current))
        .monospacedDigit()
        .fixedSize()
        .accessibilityLabel(Spoken.spend(SpendFigure(cents: cents, isEstimate: true), currency: currency,
                                         hideCents: hideCents, locale: .current))
        .accessibilityIdentifier("dashboard.account.byModel.est.\(row.model)")
    } else {
      Text(Strings.unpricedModel)
        .fontWeight(.medium)
        .foregroundStyle(Color(.healthWatch))
        .fixedSize()
        .help(Strings.unpricedModelHelp)
        .accessibilityIdentifier("dashboard.account.byModel.est.\(row.model)")
    }
  }

  private func provider(_ row: ModelRow) -> some View {
    Text(row.providerCents.map { money($0) } ?? Strings.noProviderCost)
      .monospacedDigit()
      .fixedSize()
      .foregroundStyle(row.providerCents == nil ? Color.secondary : Color.primary)
      .help(row.providerCents == nil ? Strings.noProviderCostHelp : "")
      .accessibilityIdentifier("dashboard.account.byModel.provider.\(row.model)")
  }

  @ViewBuilder private func drift(_ row: ModelRow) -> some View {
    if let drift = row.drift {
      let percent = Formatters.signedPercent(basisPoints: drift.basisPoints, locale: .current)
      HStack(spacing: 4) {
        if drift.flagged {
          Image(systemName: "exclamationmark.triangle.fill")
            .imageScale(.small)
            .accessibilityHidden(true)
        }
        Text(percent).monospacedDigit()
      }
      .fixedSize()
      .fontWeight(drift.flagged ? .semibold : .regular)
      .foregroundStyle(drift.flagged ? Color(.healthWatch) : Color.primary)
      .help(Strings.driftHelp(days: drift.days,
                              estimate: Formatters.spend(SpendFigure(cents: drift.estCents, isEstimate: true),
                                                         currency: currency, hideCents: false, locale: .current),
                              provider: Formatters.money(Money(cents: drift.providerCents, currency: currency),
                                                         hideCents: false, locale: .current)))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Strings.driftLabel(percent, flagged: drift.flagged, thresholdPct: thresholdPct))
      .accessibilityIdentifier("dashboard.account.byModel.drift.\(row.model)")
    } else {
      Text(Strings.noProviderCost)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("dashboard.account.byModel.drift.\(row.model)")
    }
  }

  private func money(_ cents: Int64) -> String {
    Formatters.money(Money(cents: cents, currency: currency), hideCents: hideCents, locale: .current)
  }
}
