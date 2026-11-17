import Charts
import SwiftUI
import TokenBeCore

/// 08 § Overview 3, **Spend by day** (14 § Stage 8.2): Swift Charts stacked bars, one stack per UTC day of the
/// Dashboard range, one segment per USD account in O-3's palette by sidebar order; hovering a day lists its accounts
/// and total. Every figure comes from Core (`SpendChart`, 04 I3). The chart is built only while the card is on
/// screen (`onAppear` / `onDisappear`), so a hidden Overview costs nothing. Without spend it reads
/// `No spend in this range` (the empty state since 1.2).
struct SpendByDayChart: View {
  let accounts: [AccountSummary]
  let hideCents: Bool
  @State private var visible = false
  @State private var hoveredDay: String?

  /// O-3: blue, purple, teal, orange, pink, indigo, mint, brown, assigned by sidebar order.
  static let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .mint, .brown]

  static func color(_ index: Int) -> Color { palette[index % palette.count] }

  var body: some View {
    let data = SpendChart.data(accounts)
    VStack(alignment: .leading, spacing: 12) {
      Text(Strings.spendByDay)
        .font(.headline)
        .accessibilityIdentifier("dashboard.spendByDay.title")
      if data.isEmpty {
        Text(Strings.noSpendInRange)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 160)
          .accessibilityIdentifier("dashboard.spendByDay.empty")
      } else {
        Group {
          if visible { chart(data) } else { Color.clear }
        }
        .frame(height: 220)
        legend(data)
      }
      if data.nonUSD > 0 {
        Text(Strings.chartNonUSD(data.nonUSD))
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("dashboard.spendByDay.nonUSD")
      }
    }
    .padding(16)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .onAppear { visible = true }
    .onDisappear { visible = false }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.spendByDay")
  }

  private func chart(_ data: SpendChartData) -> some View {
    Chart {
      ForEach(data.segments) { segment in
        // Plotted in whole cents, so no money is ever a `Double`; the axis prints the ticks as money.
        BarMark(x: .value("Day", segment.day), y: .value("Spend", segment.figure.cents))
          .foregroundStyle(Self.color(segment.colorIndex))
          .accessibilityLabel(Strings.chartSegment(account: segment.label, day: Formatters.day(segment.day)))
          .accessibilityValue(money(segment.figure))
      }
      if let hoveredDay, let total = data.dayTotals[hoveredDay] {
        // Swift Charts does not expose an annotation's text, so the rule carries the tooltip's total for VoiceOver.
        RuleMark(x: .value("Day", hoveredDay))
          .foregroundStyle(.secondary.opacity(0.25))
          .accessibilityLabel(Strings.chartTotalOn(Formatters.day(hoveredDay), amount: money(total)))
          .annotation(position: .top, alignment: .center, spacing: 4,
                      overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
            tooltip(data, day: hoveredDay)
          }
      }
    }
    .chartXScale(domain: data.days)
    .chartXAxis {
      // A category axis marks every day whatever `values` says, so only `axisDays` (at most 8) get a label.
      let labelled = Set(data.axisDays)
      AxisMarks { value in
        if let day = value.as(String.self), labelled.contains(day) {
          AxisValueLabel { Text(Formatters.day(day)) }
        }
      }
    }
    .chartYAxis {
      AxisMarks { value in
        AxisGridLine()
        AxisValueLabel {
          // Whole dollars without cents; a tick between dollars keeps them, so ticks never repeat (`$0.25`).
          Text(value.as(Int64.self).map {
            Formatters.money(Money(cents: $0, currency: .usd), hideCents: $0 % 100 == 0, locale: .current)
          } ?? "")
        }
      }
    }
    .chartOverlay { proxy in hoverArea(proxy) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Strings.spendByDayChart)
    .accessibilityIdentifier("dashboard.spendByDay.chart")
  }

  /// Tracks the pointer over the plot: the day under it opens the tooltip; leaving closes it.
  private func hoverArea(_ proxy: ChartProxy) -> some View {
    GeometryReader { geometry in
      Rectangle().fill(.clear).contentShape(Rectangle())
        .onContinuousHover { phase in
          switch phase {
          case .active(let location):
            guard let frame = proxy.plotFrame else { return }
            hoveredDay = proxy.value(atX: location.x - geometry[frame].origin.x, as: String.self)
          case .ended:
            hoveredDay = nil
          }
        }
    }
  }

  /// The hovered day's accounts and total (08: "hover tooltip lists accounts").
  private func tooltip(_ data: SpendChartData, day: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(Formatters.day(day)).font(.caption.weight(.semibold))
      ForEach(data.segments(on: day)) { segment in
        HStack(spacing: 6) {
          Circle().fill(Self.color(segment.colorIndex)).frame(width: 7, height: 7)
          Text(segment.label)
          Spacer(minLength: 12)
          Text(money(segment.figure)).monospacedDigit()
        }
      }
      if let total = data.dayTotals[day] {
        Divider()
        HStack {
          Text(Strings.chartTotal)
          Spacer(minLength: 12)
          Text(money(total)).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
      }
    }
    .font(.caption)
    .padding(8)
    .frame(minWidth: 160)
    .background(.background, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
  }

  private func legend(_ data: SpendChartData) -> some View {
    HStack(spacing: 14) {
      ForEach(data.accounts) { account in
        HStack(spacing: 5) {
          Circle().fill(Self.color(account.colorIndex)).frame(width: 8, height: 8)
          Text(account.label).font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.spendByDay.legend.\(account.id)")
      }
    }
  }

  private func money(_ figure: SpendFigure) -> String {
    Formatters.spend(figure, currency: .usd, hideCents: hideCents, locale: .current)
  }
}
