import SwiftUI
import TokenBeCore

/// One account card (08 § Popover 3). Row 1: label, mode chip, band dot. Row 2: the pinned metric
/// (09 `tb.popover.pinnedMetric`), or "No data yet"; row 3: the other two metrics (`CardRows`), Day-1's
/// `Collecting…`, `reloads at $X`, or a spend-only account's `today $3.10 · 30 d $84` (5.3). Row 4 (7.1): the top
/// apps by today's spend behind a chevron, collapsed by default, remembered in 09 `tb.popover.expanded.<provider>`.
/// The stale overlay (08: opacity 0.6, freshness `stale · 3 h ago` in `HealthLow`) covers a stale account, and every
/// card while offline, so the state is in the text too, not only in the opacity (08 § Accessibility). A click opens
/// the account's page in the Dashboard (08).
struct AccountCardView: View {
  let summary: AccountSummary
  /// Stale, or the Mac is offline (08 § Popover states).
  let dimmed: Bool
  /// Keyboard focus (↑/↓, 08 § Popover 4): an accent outline.
  var isFocused = false
  /// `Key missing · Fix…` opens Settings → Accounts (08).
  let fixKey: () -> Void
  let open: () -> Void
  @Environment(\.appEnvironment) private var environment
  @State private var appsExpanded = false
  @Environment(\.dynamicTypeSize) private var textSize

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        ProviderGlyph(provider: summary.provider, size: 16)
        Text(summary.label)
          .scaledFont(13, weight: .bold)
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).label")
        if let chip = modeChip {
          Text(chip)
            .scaledFont(10)
            .foregroundStyle(.secondary)
        }
        Spacer()
        BandDot(band: summary.band)
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).band")
      }
      if summary.needsKey {
        Button(Strings.keyMissingFix, action: fixKey)
          .buttonStyle(.link)
          .scaledFont(13, weight: .semibold)
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).fixKey")
      } else {
        let rows = self.rows
        // VoiceOver reads each figure's title and its words, never the symbols (08 § Accessibility).
        Text(rows.row2 ?? Strings.noDataYet)
          .scaledFont(20, weight: .semibold, monospacedDigits: true)
          .accessibilityLabel(rows.spoken2 ?? Strings.noDataYet)
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).pinned")
        if !rows.row3.isEmpty {
          Text(rows.row3.joined(separator: " \u{00B7} "))
            .scaledFont(10, monospacedDigits: true)
            .foregroundStyle(.secondary)
            .accessibilityLabel(rows.spoken3.joined(separator: ", "))
            .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).row3")
        }
      }
      if let apps = appsText {
        appsRow(apps)
      }
      Text(Formatters.freshness(summary.lastSuccessAt, now: Date(), calendar: .current, stale: dimmed))
        .scaledFont(10, monospacedDigits: true)
        .foregroundStyle(dimmed ? Color(.healthLow) : Color.secondary)
        .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).freshness")
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.ground), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      if isFocused { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2) }
    }
    .opacity(dimmed ? 0.6 : 1)
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .onTapGesture(perform: open)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("popover.card.\(summary.provider.rawValue)")
    .onAppear { appsExpanded = environment?.settings.isPopoverExpanded(summary.provider) ?? false }
  }

  /// Row 4 (08): the chevron, then `Apps` collapsed or `weather-collector $1.20 · harness $0.40 · other $0.10`.
  private func appsRow(_ apps: String) -> some View {
    Button {
      appsExpanded.toggle()
      environment?.settings.setPopoverExpanded(summary.provider, appsExpanded)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: appsExpanded ? "chevron.down" : "chevron.right")
          .scaledFont(10, weight: .semibold)
        Text(appsExpanded ? apps : Strings.apps)
          .scaledFont(10, monospacedDigits: true)
          // Larger text reflows to a second line (08 § Accessibility).
          .lineLimit(textSize > .large ? 2 : 1)
      }
      .foregroundStyle(.secondary)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(appsExpanded ? apps : Strings.showApps)
    .accessibilityHint(appsExpanded ? Strings.hideApps : Strings.showApps)
    .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).appsToggle")
  }

  /// The top 3 apps by today's spend (Core `Attribution.top`); nil when no app spent anything today.
  private var appsText: String? {
    let top = Attribution.top(summary.todayApps)
    guard !top.rows.isEmpty else { return nil }
    let hideCents = environment?.settings.uiHideCents ?? true
    func spend(_ figure: SpendFigure) -> String {
      Formatters.spend(figure, currency: summary.currency, hideCents: hideCents, locale: .current)
    }
    var entries = top.rows.map { Strings.appEntry(Strings.appLabel($0), spend($0.spend)) }
    if let other = top.other { entries.append(Strings.appEntry(Strings.otherApps, spend(other))) }
    return entries.joined(separator: " \u{00B7} ")
  }

  private var modeChip: String? {
    switch summary.mode {
    case .direct: nil
    case .anchored: Strings.modeAnchored
    case .spendOnly: Strings.modeSpendOnly
    }
  }

  /// Rows 2 and 3, as shown and as VoiceOver reads them (`spoken2`, `spoken3`: the same metrics in the same places,
  /// each with its title, 08 § Accessibility). Before the first successful poll row 2 reads "No data yet" and row 3
  /// is empty (08).
  private var rows: CardText {
    guard summary.lastSuccessAt != nil || summary.hasHarness else { return CardText() }
    let hideCents = environment?.settings.uiHideCents ?? true
    let figures = CardFigures(summary: summary, hideCents: hideCents)
    if summary.mode == .spendOnly {
      let thirty = summary.spend30dCents.map { Strings.spend30d(figures.money($0)) }
      let spokenThirty = summary.spend30dCents.map { Strings.spoken(Strings.spoken30d, figures.spokenMoney($0)) }
      return CardText(row2: figures.today, row3: [figures.today.map(Strings.todaySpend), thirty].compactMap { $0 },
                      spoken2: figures.spokenToday, spoken3: [figures.spokenToday, spokenThirty].compactMap { $0 })
    }
    // Day-1 has no runway value: the next metric takes row 2 and `Collecting…` closes row 3 (08).
    let collecting = summary.burn7dCents == nil && !summary.reloadPending && !summary.needsAnchor
    let values: [CardRows.Metric: String] = [
      .remaining: figures.remaining, .runway: collecting ? nil : figures.runway,
      .todaySpend: figures.today.map(Strings.todaySpend)
    ].compactMapValues { $0 }
    let spoken: [CardRows.Metric: String] = [
      .remaining: figures.spokenRemaining, .runway: collecting ? nil : figures.spokenRunway,
      .todaySpend: figures.spokenToday
    ].compactMapValues { $0 }
    let pinned = CardRows.Metric(rawValue: environment?.settings.popoverPinnedMetric ?? "runway") ?? .runway
    var rows = CardRows.rows(pinned: pinned, values: values)
    let words = CardRows.rows(pinned: pinned, values: spoken)
    // The pinned metric itself reads without its `today` prefix in row 2.
    if pinned == .todaySpend, let today = figures.today, rows.row2 == values[.todaySpend] { rows.row2 = today }
    var spoken3 = words.row3
    if collecting {
      rows.row3.append(Strings.collecting)
      spoken3.append(Strings.collecting)
    }
    return CardText(row2: rows.row2, row3: rows.row3, spoken2: words.row2, spoken3: spoken3)
  }
}

/// Rows 2 and 3 as shown, and as VoiceOver reads them.
private struct CardText {
  var row2: String?
  var row3: [String] = []
  var spoken2: String?
  var spoken3: [String] = []
}

/// A card's figures, as shown (`≈ $42 ± 3`, `~12 d · ~9 d today`, `reloads at $X`, Day-1 `Collecting…`; 05, 08) and
/// as VoiceOver reads them with their titles (`Remaining, approximately 42 dollars, plus or minus 3`).
private struct CardFigures {
  let summary: AccountSummary
  let hideCents: Bool

  func money(_ cents: Int64) -> String {
    Formatters.money(Money(cents: cents, currency: summary.currency), hideCents: hideCents, locale: .current)
  }

  func spokenMoney(_ cents: Int64) -> String {
    Spoken.money(Money(cents: cents, currency: summary.currency), hideCents: hideCents, locale: .current)
  }

  var today: String? {
    summary.todaySpend.map { Formatters.spend($0, currency: summary.currency, hideCents: hideCents, locale: .current) }
  }

  var spokenToday: String? {
    summary.todaySpend.map {
      Strings.spoken(Strings.spendToday, Spoken.spend($0, currency: summary.currency, hideCents: hideCents,
                                                       locale: .current))
    }
  }

  /// `≈ $42 ± 3` for an anchored account, `$42` for a direct one (08).
  var remaining: String? {
    guard let cents = summary.remainingCents else { return nil }
    let amount = Money(cents: cents, currency: summary.currency)
    if summary.mode == .anchored, let band = summary.estimateBandCents {
      return Formatters.estimate(amount, bandCents: band, hideCents: hideCents, locale: .current)
    }
    return Formatters.remaining(amount, hideCents: hideCents, locale: .current)
  }

  var spokenRemaining: String? {
    guard let cents = summary.remainingCents else { return nil }
    let amount = Money(cents: cents, currency: summary.currency)
    if summary.mode == .anchored, let band = summary.estimateBandCents {
      return Strings.spoken(Strings.remaining,
                            Spoken.estimate(amount, bandCents: band, hideCents: hideCents, locale: .current))
    }
    return Strings.spoken(Strings.remaining, Spoken.remaining(amount, hideCents: hideCents, locale: .current))
  }

  /// `~12 d · ~9 d today`; `reloads at $X` (05); Day-1 `Collecting…` while `burn_7d` is nil (08).
  var runway: String? {
    if summary.reloadPending, let reload = summary.autoReload { return Strings.reloadsAt(money(reload.belowCents)) }
    if summary.burn7dCents == nil { return summary.needsAnchor ? nil : Strings.collecting }
    return Formatters.runwayPair(sevenDay: summary.runway7d, today: summary.runwayToday)
  }

  var spokenRunway: String? {
    if summary.reloadPending, let reload = summary.autoReload {
      return Strings.spoken(Strings.runway, Strings.reloadsAt(spokenMoney(reload.belowCents)))
    }
    if summary.burn7dCents == nil { return summary.needsAnchor ? nil : Strings.collecting }
    return Spoken.runwayPair(sevenDay: summary.runway7d, today: summary.runwayToday)
      .map { Strings.spoken(Strings.runway, $0) }
  }
}
