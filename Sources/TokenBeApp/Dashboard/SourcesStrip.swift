import SwiftUI
import TokenBeCore

/// 08 `HP-0`: one entry per data source with its state, last success and next run, e.g.
/// `Usage · ok · 2 min ago · next 3 min`, `Cost · ok · 02:10`, `Balance · n/a`. A failed source is in `HealthLow`
/// with its last error's human message (Q-036). Laid out as Paper's strip: a grey panel of columns, each a caption
/// title over its line. `Harness · …` joins in 7.2.
struct SourcesStrip: View {
  let sources: [SourceStatus]

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      HStack(alignment: .top, spacing: 28) {
        ForEach(sources) { source in
          column(source, now: context.date)
        }
        Spacer(minLength: 0)
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
