import SwiftUI

/// Privacy tab (08 § Settings, Paper `1C7-0`): static statements and `Open log folder`. The update-check row
/// arrives in 9.4.
struct PrivacyTab: View {
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
        OpenLogFolderButton(logsDirectory: logsDirectory)
          .accessibilityIdentifier("settings.privacy.openLogFolder")
      }
    }
    .formStyle(.grouped)
  }
}
