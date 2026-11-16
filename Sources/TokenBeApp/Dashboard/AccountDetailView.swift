import SwiftUI
import TokenBeCore

/// 08 § Account detail (Paper `8T-0`): the header (`AM-0`, `AR-0`) with `Set anchor…` (anchored), `Add top-up…` and
/// `Refresh`; the badges row (`B1-0`); the anchor nudges (09 `tb.alerts.anchorAgeDays`, 04 V1); the numbers strip;
/// the By-app table (`20N-0`, 7.1), filtered to one app from the Overview (7.3); the harness drift chip beside the
/// band pill (7.3); the By-model table (`G7-0`, 8.1); the sources strip (`HP-0`); the ledger list (anchored).
struct AccountDetailView: View {
  let model: AppModel
  let summary: AccountSummary
  /// The Dashboard's app filter; this page applies it only when it names this account.
  @Binding var filter: AppFilter?
  @State private var sheet: LedgerEntryForm.Kind?
  @Environment(\.openSettings) private var openSettings

  private var record: AccountRecord? { model.records.first { $0.id == summary.id } }
  private var settings: TokenBeCore.Settings? { model.environment?.settings }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        if let capabilities = summary.capabilities {
          BadgesRow(provider: summary.provider, badges: AccountBadges(mode: summary.mode, capabilities: capabilities))
        }
        nudge
        NumbersStrip(summary: summary, hideCents: settings?.uiHideCents ?? true)
        if summary.byApp.isEmpty {
          // 08: the empty By-app table points at Settings → Sources → Harness reports.
          Button(Strings.reportAppsFromHarness) {
            model.settingsTab = .sources
            openSettings()
            NSApp.activate()
          }
          .buttonStyle(.link)
          .accessibilityIdentifier("dashboard.account.byApp.empty")
        } else {
          ByAppTable(model: model, summary: summary, hideCents: settings?.uiHideCents ?? true,
                     filter: filter?.accountID == summary.id ? filter : nil) { filter = nil }
        }
        // 8.1: shown once the range has usage; 08 gives the table no empty state (Q-051).
        if !summary.byModel.isEmpty {
          ByModelTable(rows: summary.byModel, currency: summary.currency, hideCents: settings?.uiHideCents ?? true,
                       thresholdPct: settings?.alertsDriftThresholdPct ?? 10)
        }
        SourcesStrip(sources: summary.sources, prices: model.environment?.prices?.status,
                     harness: summary.hasHarness ? (model.ingestStatus.files, summary.harnessLinesToday) : nil)
        if summary.mode == .anchored {
          LedgerList(events: model.ledgerEvents.filter { $0.accountId == summary.id }, currency: summary.currency,
                     hideCents: settings?.uiHideCents ?? true) { event in
            deleteLedgerEvent(event)
          }
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(summary.label)
    .accessibilityIdentifier("dashboard.account")
    .sheet(item: $sheet) { kind in
      if let record {
        switch kind {
        case .anchor: SetAnchorSheet(account: record, lifecycle: model.environment?.lifecycle)
        case .topUp: AddTopUpSheet(account: record, lifecycle: model.environment?.lifecycle)
        }
      }
    }
  }

  /// V1 broke (re-anchor), or the anchor is older than `tb.alerts.anchorAgeDays` (09), with `Set anchor…`.
  @ViewBuilder private var nudge: some View {
    let ageLimit = settings?.alertsAnchorAgeDays ?? 30
    let text: String? = if summary.needsReanchor {
      Strings.reanchor
    } else if let age = summary.anchorAgeDays, age > ageLimit {
      Strings.anchorOld(age)
    } else {
      nil
    }
    if let text {
      HStack(spacing: 8) {
        Text(text)
          .font(.callout)
          .foregroundStyle(Color(.healthWatch))
          .accessibilityIdentifier("dashboard.account.nudge")
        Button(Strings.setAnchor) { sheet = .anchor }
          .buttonStyle(.link)
      }
    }
  }

  private func deleteLedgerEvent(_ event: LedgerEventRecord) {
    guard let lifecycle = model.environment?.lifecycle else { return }
    Task {
      do {
        try await lifecycle.deleteLedgerEvent(id: event.id)
      } catch {
        Log.error(.uiError, cat: .ui, msg: "ledger row not deleted", acct: summary.provider.rawValue, err: error,
                  ctx: ["view": "ledger"])
      }
    }
  }

  /// Provider glyph, label, mode chip, band pill, the unavailable chip (direct providers) and freshness; `Refresh`
  /// on the right.
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
          if summary.providerUnavailable {
            // D-deepseek-unavailable: the provider's hard stop, beside the band it forces to critical.
            Text(Strings.providerUnavailable)
              .font(.callout.weight(.medium))
              .foregroundStyle(Color(.healthCritical))
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Color(.healthCritical).opacity(0.12), in: Capsule())
              .accessibilityIdentifier("dashboard.account.unavailable")
          }
          DriftChip(drift: summary.harnessDrift, currency: summary.currency, hideCents: settings?.uiHideCents ?? true)
        }
        TimelineView(.periodic(from: .now, by: 30)) { context in
          Text(Formatters.freshness(summary.lastSuccessAt, now: context.date, calendar: .current, stale: dimmed))
            .font(.callout.monospacedDigit())
            .foregroundStyle(dimmed ? Color(.healthLow) : Color.secondary)
            .accessibilityIdentifier("dashboard.account.freshness")
        }
      }
      Spacer()
      HStack(spacing: 8) {
        if summary.mode == .anchored {
          Button(Strings.setAnchor) { sheet = .anchor }
            .accessibilityIdentifier("dashboard.account.setAnchor")
        }
        Button(Strings.addTopUp) { sheet = .topUp }
          .accessibilityIdentifier("dashboard.account.addTopUp")
        Button(Strings.refresh) { model.refreshNow(summary.id) }
          .accessibilityIdentifier("dashboard.account.refresh")
      }
      .padding(.top, 4)
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

extension LedgerEntryForm.Kind: Identifiable {
  var id: String { rawValue }
}
