import AppKit
import SwiftUI
import TokenBeCore

/// The popover (08 § Popover; width 360 pt, max height 560 pt, scrolls): the header (title; `Refreshed …` and the
/// refresh button, or `Paused · resumes HH:mm` and `Resume`), the banner slot, the Empty state or the card list,
/// and the footer with `Open dashboard`, `Settings…`, `Pause polling for 1 h` / `Resume` and `Quit`.
struct PopoverView: View {
  let model: AppModel
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      if model.isOffline { offlineBanner }
      content
      Divider()
      footer
    }
    .frame(width: 360)
    .frame(maxHeight: 560)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("popover.root")
    .onAppear {
      model.popoverDidOpen()
      // 08: ⌥-click on the glyph opens the Dashboard. The modifier is read as the popover appears (O-15).
      if NSEvent.modifierFlags.contains(.option) { openDashboard() }
    }
    .onDisappear { model.popoverDidClose() }
  }

  private func openDashboard() {
    openWindow(id: DashboardView.windowID)
    NSApp.activate()
    dismiss()
  }

  /// A menu-bar app is not active when its popover is clicked, so the Settings window is brought forward.
  private func showSettings() {
    openSettings()
    NSApp.activate()
    dismiss()
  }

  private var header: some View {
    HStack {
      Text(Strings.appName)
        .font(.headline)
        .accessibilityIdentifier("popover.header.title")
      Spacer()
      if let until = model.pausedUntil {
        Text(Strings.pausedResumes(Formatters.clockTime(until, calendar: .current)))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("popover.header.paused")
        Button(Strings.resume) { model.resume() }
          .buttonStyle(.link)
          .font(.caption)
          .accessibilityIdentifier("popover.header.resume")
      } else {
        if let refreshed = model.lastRefreshAt {
          // Re-rendered every 30 s while the popover is open, so `2 min ago` keeps counting (no Timer, R6).
          TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Strings.refreshed(Formatters.freshness(refreshed, now: context.date, calendar: .current)))
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("popover.header.freshness")
          }
        }
        if !model.accounts.isEmpty { refreshButton }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var refreshButton: some View {
        Button {
          model.refreshNow()
        } label: {
          Image(systemName: "arrow.clockwise")
            // Spins while any job is in flight (08); symbol effects follow Reduce Motion.
            .symbolEffect(.rotate, options: .repeat(.continuous), isActive: model.inFlightCount > 0)
        }
        .buttonStyle(.borderless)
        .help(Strings.refresh)
        .accessibilityLabel(Strings.refresh)
        .accessibilityValue(model.inFlightCount > 0 ? "refreshing" : "idle")
        .accessibilityIdentifier("popover.header.refresh")
  }

  @ViewBuilder private var content: some View {
    if model.accounts.isEmpty {
      EmptyStateView {
        dismiss()
        model.showOnboarding()
      }
    } else {
      // The cards size the popover while they fit; past 08's 560 pt they scroll inside a fixed height.
      ViewThatFits(in: .vertical) {
        cards
        ScrollView { cards }
          .frame(height: Self.maxCardsHeight)
      }
      // No identifier here: SwiftUI hands it to a lone card, which then loses `popover.card.<provider>` (4.2).
    }
  }

  /// 08 § Popover states, Offline: a single line in the secondary tone, not a band colour.
  private var offlineBanner: some View {
    Text(Strings.offlineBanner)
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(Color.secondary.opacity(0.12))
      .accessibilityIdentifier("popover.banner.offline")
  }

  /// 560 pt (08) minus the header and the two-row footer.
  static let maxCardsHeight: CGFloat = 430

  private var cards: some View {
    VStack(spacing: 8) {
      ForEach(model.sortedAccounts) { summary in
        AccountCardView(summary: summary, dimmed: summary.isStale || model.isOffline) {
          model.settingsTab = .accounts
          showSettings()
        } open: {
          model.showAccount(summary.id)
          dismiss()
        }
      }
    }
    .padding(12)
  }

  /// 08's four footer actions do not fit one 360 pt row, so they wrap to two (Q-034; Paper check in 11.3).
  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button(Strings.openDashboard) { openDashboard() }
          .keyboardShortcut("d")
          .accessibilityIdentifier("popover.footer.openDashboard")
        Button(Strings.settingsEllipsis) { showSettings() }
          .keyboardShortcut(",")
          .accessibilityIdentifier("popover.footer.settings")
      }
      HStack {
        if model.isPaused {
          Button(Strings.resume) { model.resume() }
            .accessibilityIdentifier("popover.footer.resume")
        } else {
          Button(Strings.pausePolling) { model.pauseForOneHour() }
            .accessibilityIdentifier("popover.footer.pause")
        }
        Spacer()
        Button(Strings.quit) {
          NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
        .accessibilityIdentifier("popover.footer.quit")
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}
