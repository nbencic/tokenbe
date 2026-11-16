import SwiftUI
import TokenBeCore

/// 08 `HP-0`: one entry per data source with its state, last success and next run, e.g.
/// `Usage · ok · 2 min ago · next 3 min`, `Cost · ok · 02:10`, `Balance · n/a`. A failed source is in `HealthLow`
/// with its last error's human message (Q-036). Laid out as Paper's strip: a grey panel of columns, each a caption
/// title over its line. The last column is the price snapshot's chip, `Prices · Nov 8 · ok` or `· stale` in
/// `HealthWatch` (14 § Stage 5.1 step 6). An account with harness lines adds `Harness · 3 files · 12 lines today`
/// (7.2: the files the ingest service reads, this account's lines today). The columns wrap to the window's width, so
/// the strip never makes the account page wider than the Dashboard's 920 pt minimum (7.1). The columns are not lazy
/// (PM-7.2-6, 8.1): every chip exists for VoiceOver and the UI tests even below the fold, which the By-model table
/// (8.1) pushed the strip to.
struct SourcesStrip: View {
  let sources: [SourceStatus]
  /// Nil before startup step 4 (no chip).
  var prices: PriceBook.Status?
  /// Files being read and this account's lines today; nil when the account has no harness lines (no chip).
  var harness: (files: Int, linesToday: Int)?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      AdaptiveColumns(minimum: 200, spacing: 28, rowSpacing: 12) {
        ForEach(sources) { source in
          column(source, now: context.date)
        }
        if let prices, let line = Self.pricesLine(prices) {
          VStack(alignment: .leading, spacing: 2) {
            Text(Strings.sourcePrices)
              .font(.caption2.weight(.semibold))
              .textCase(.uppercase)
              .foregroundStyle(.tertiary)
            Text(line)
              .font(.caption.monospacedDigit())
              .foregroundStyle(prices.isStale ? Color(.healthWatch) : Color.primary)
          }
          .frame(width: 140, alignment: .leading)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Strings.sourceLine([Strings.sourcePrices, line]))
          .accessibilityIdentifier("dashboard.account.source.prices")
        }
        if let harness {
          let line = Strings.harnessLine(files: harness.files, linesToday: harness.linesToday)
          VStack(alignment: .leading, spacing: 2) {
            Text(Strings.sourceHarness)
              .font(.caption2.weight(.semibold))
              .textCase(.uppercase)
              .foregroundStyle(.tertiary)
            Text(line)
              .font(.caption.monospacedDigit())
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Strings.sourceLine([Strings.sourceHarness, line]))
          .accessibilityIdentifier("dashboard.account.source.harness")
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.window), in: RoundedRectangle(cornerRadius: 10))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.account.sources")
  }

  private func column(_ source: SourceStatus, now: Date) -> some View {
    let line = Self.line(source, now: now)
    return VStack(alignment: .leading, spacing: 2) {
      Text(Self.title(source.job))
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(.tertiary)
      Text(line)
        .font(.caption.monospacedDigit())
        .foregroundStyle(source.state == .failed ? Color(.healthLow) : Color.primary)
      if source.state == .failed, let message = source.message {
        Text(message)
          .font(.caption)
          .foregroundStyle(Color(.healthLow))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(width: 200, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Strings.sourceLine([Self.title(source.job), line] + (source.state == .failed ? [source.message ?? ""] : [])))
    .accessibilityIdentifier("dashboard.account.source.\(source.job.rawValue)")
  }

  static func title(_ job: Job) -> String {
    switch job {
    case .usage: Strings.sourceUsage
    case .cost: Strings.sourceCost
    case .balance: Strings.sourceBalance
    case .keys: Strings.sourceKeys
    }
  }

  /// `Nov 8 · ok`: the day of the snapshot's last successful fetch or check, and whether it is stale; nil without a
  /// snapshot.
  static func pricesLine(_ status: PriceBook.Status) -> String? {
    guard let fetched = status.fetchedAt else { return nil }
    return Strings.sourceLine([Formatters.date(fetched, calendar: .current),
                               status.isStale ? Strings.sourceStale : Strings.sourceOK])
  }

  /// `ok · 2 min ago · next 3 min`; the daily `cost` job shows the time of its last success (`ok · 02:10`).
  static func line(_ source: SourceStatus, now: Date) -> String {
    var parts: [String]
    switch source.state {
    case .notApplicable: return Strings.sourceNotApplicable
    case .succeeded: parts = [Strings.sourceOK]
    case .failed: parts = [Strings.sourceFailed]
    case .never: parts = []
    }
    if source.job == .cost, let success = source.lastSuccessAt {
      parts.append(Formatters.clockTime(success, calendar: .current))
    } else {
      parts.append(Formatters.freshness(source.lastSuccessAt, now: now, calendar: .current))
    }
    if let due = source.nextDue { parts.append(Strings.next(Formatters.untilNextRun(due, now: now))) }
    return Strings.sourceLine(parts)
  }
}

/// `LazyVGrid`'s `.adaptive(minimum:)` columns without the laziness: as many equal columns as fit at `minimum` wide,
/// filled row by row, each row as tall as its tallest cell, every cell top-leading (PM-7.2-6).
struct AdaptiveColumns: Layout {
  let minimum: CGFloat
  let spacing: CGFloat
  let rowSpacing: CGFloat

  private func columns(_ width: CGFloat) -> (count: Int, width: CGFloat) {
    let count = max(1, Int((width + spacing) / (minimum + spacing)))
    return (count, max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count)))
  }

  private func rowHeights(_ subviews: Subviews, count: Int, width: CGFloat) -> [CGFloat] {
    stride(from: 0, to: subviews.count, by: count).map { start in
      subviews[start..<min(start + count, subviews.count)]
        .map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0
    }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? (minimum + spacing) * CGFloat(max(1, subviews.count)) - spacing
    let grid = columns(width)
    let heights = rowHeights(subviews, count: grid.count, width: grid.width)
    return CGSize(width: width, height: heights.reduce(0, +) + rowSpacing * CGFloat(max(0, heights.count - 1)))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let grid = columns(bounds.width)
    let heights = rowHeights(subviews, count: grid.count, width: grid.width)
    var top = bounds.minY
    for (index, subview) in subviews.enumerated() {
      let row = index / grid.count
      let column = index % grid.count
      if column == 0 && row > 0 { top += heights[row - 1] + rowSpacing }
      subview.place(at: CGPoint(x: bounds.minX + CGFloat(column) * (grid.width + spacing), y: top), anchor: .topLeading,
                    proposal: ProposedViewSize(width: grid.width, height: nil))
    }
  }
}
