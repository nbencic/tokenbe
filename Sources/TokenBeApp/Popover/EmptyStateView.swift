import SwiftUI

/// 08 § Popover states — Empty (Paper `45-0`): no illustration, headline, body and `Add account…` (onboarding).
struct EmptyStateView: View {
  let addAccount: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      Text(Strings.emptyHeadline)
        .font(.headline)
        .accessibilityIdentifier("popover.empty.headline")
      Text(Strings.emptyBody)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("popover.empty.body")
      Button(Strings.addAccount, action: addAccount)
        .buttonStyle(.borderedProminent)
        .padding(.top, 8)
        .accessibilityIdentifier("popover.empty.addAccount")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
    .padding(.horizontal, 24)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("popover.empty")
  }
}
