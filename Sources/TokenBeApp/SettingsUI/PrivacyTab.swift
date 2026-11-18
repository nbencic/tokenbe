import SwiftUI
import TokenBeCore

/// Privacy tab (08 § Settings, Paper `1C7-0`): static statements; the update-check row (`1U1-0`/`1U2-0`:
/// `Check for updates daily` with 08's caption, 09 `tb.update.checkEnabled`) and its `Update available` badge
/// (14 § Stage 9.4); `Open log folder`.
struct PrivacyTab: View {
  @Bindable var settings: TokenBeCore.Settings
  let updates: UpdateModel
  let logsDirectory: URL

  var body: some View {
    Form {
      Section {
        Label(Strings.privacyKeys, systemImage: "key")
          .accessibilityIdentifier("settings.privacy.keys")
        Label(Strings.privacyTelemetry, systemImage: "eye.slash")
          .accessibilityIdentifier("settings.privacy.telemetry")
      }
      Section {
        Toggle(isOn: $settings.updateCheckEnabled) {
          Text(Strings.checkForUpdatesDaily)
          Text(Strings.checkForUpdatesCaption)
        }
        .accessibilityIdentifier("settings.privacy.checkForUpdates")
        UpdateBadge(updates: updates, place: "settings.privacy")
      }
      Section {
        OpenLogFolderButton(logsDirectory: logsDirectory)
          .accessibilityIdentifier("settings.privacy.openLogFolder")
      }
    }
    .formStyle(.grouped)
  }
}
