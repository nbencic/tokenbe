import SwiftUI
import TokenBeCore

/// Advanced tab (08 § Settings, Paper `1WN-0`, `22Q-0`): log level (live, 07), log retention, `Open log folder`.
/// Diagnostics, maintenance and data rows arrive in 2.2 and 9.x.
struct AdvancedTab: View {
  @Bindable var settings: TokenBeCore.Settings
  let logsDirectory: URL

  var body: some View {
    Form {
      Section {
        Picker(Strings.logLevel, selection: $settings.logLevel) {
          Text(Strings.logLevelDebug).tag("debug")
          Text(Strings.logLevelInfo).tag("info")
          Text(Strings.logLevelWarn).tag("warn")
          Text(Strings.logLevelError).tag("error")
        }
        .accessibilityIdentifier("settings.advanced.logLevel")
        Stepper(value: $settings.logRetentionDays, in: SettingsKey.logRetentionDays.spec.intBounds ?? 1...90) {
          LabeledContent(Strings.logRetention, value: Strings.days(settings.logRetentionDays))
        }
        .accessibilityIdentifier("settings.advanced.logRetention")
        OpenLogFolderButton(logsDirectory: logsDirectory)
          .accessibilityIdentifier("settings.advanced.openLogFolder")
      }
    }
    .formStyle(.grouped)
  }
}
