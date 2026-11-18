import SwiftUI

/// `Update available` (02, 09, 14 § Stage 9.4) with the release page and `Skip this version`; the same row in the
/// Privacy tab, at the top of the Overview and above the popover footer. Shows nothing without an update.
struct UpdateBadge: View {
  let updates: UpdateModel?
  /// `settings.privacy`, `dashboard.overview` or `popover`: the element ids' prefix.
  let place: String

  var body: some View {
    if let updates, let version = updates.available {
      HStack(spacing: 8) {
        Image(systemName: "arrow.down.circle.fill")
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 0) {
          Text(Strings.updateAvailable)
            .font(.callout.weight(.semibold))
          Text(Strings.updateVersion(version))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(place).update.badge")
        Spacer(minLength: 8)
        Button(Strings.openReleasePage) { updates.openReleasePage() }
          .disabled(updates.releasePage == nil)
          .accessibilityIdentifier("\(place).update.open")
        Button(Strings.skipThisVersion) { updates.skip() }
          .accessibilityIdentifier("\(place).update.skip")
      }
      .controlSize(.small)
    }
  }
}
