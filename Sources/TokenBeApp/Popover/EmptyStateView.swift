import SwiftUI

/// 08 § Popover states — Empty (Paper `45-0`): no illustration, headline and body.
/// The add-account button arrives with onboarding in Stage 3.5 (a control appears with its action).
struct EmptyStateView: View {
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
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
    .padding(.horizontal, 24)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("popover.empty")
  }
}
