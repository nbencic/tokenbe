import AppKit
import SwiftUI
import TokenBeCore

/// The popover (08 § Popover; width 360 pt, max height 560 pt, scrolls). Stage 1.1: header title, the banner slot,
/// the Empty state or the card list, and the footer with `Quit`. Other controls arrive with their actions.
struct PopoverView: View {
  let model: AppModel

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
    .onAppear { model.popoverDidOpen() }
    .onDisappear { model.popoverDidClose() }
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
      EmptyStateView()
    } else {
      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(model.accounts) { summary in
            AccountCardView(summary: summary)
          }
        }
        .padding(12)
      }
      .accessibilityIdentifier("popover.cards")
    }
  }

  private var footer: some View {
    HStack {
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
