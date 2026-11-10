import AppKit
import SwiftUI
import TokenBeCore

/// The popover (08 § Popover; width 360 pt, max height 560 pt, scrolls). Stage 1.1: header title, the banner slot,
/// the Empty state or the card list, and the footer with `Open dashboard`, `Settings…` and `Quit`. Other controls
/// arrive with their actions.
struct PopoverView: View {
  let model: AppModel
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
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
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
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
      .accessibilityIdentifier("popover.cards")
    }
  }

  /// 560 pt (08) minus the header and footer.
  static let maxCardsHeight: CGFloat = 460

  private var cards: some View {
    VStack(spacing: 8) {
      ForEach(model.sortedAccounts) { summary in
        AccountCardView(summary: summary) {
          model.settingsTab = .accounts
          showSettings()
        }
      }
    }
    .padding(12)
  }

  private var footer: some View {
    HStack {
      Button(Strings.openDashboard) { openDashboard() }
        .keyboardShortcut("d")
        .accessibilityIdentifier("popover.footer.openDashboard")
      Button(Strings.settingsEllipsis) { showSettings() }
        .keyboardShortcut(",")
        .accessibilityIdentifier("popover.footer.settings")
      Spacer()
      Button(Strings.quit) {
        NSApp.terminate(nil)
      }
      .keyboardShortcut("q")
      .accessibilityIdentifier("popover.footer.quit")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}
