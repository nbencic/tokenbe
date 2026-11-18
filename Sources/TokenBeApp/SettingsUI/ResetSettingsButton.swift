import SwiftUI
import TokenBeCore

/// Advanced → `Reset all settings…` (08 § Settings, 09 § Reset semantics; 14 § Stage 9.5): a destructive confirm,
/// then `Settings.resetAll()`. It removes every `tb.*` key except `tb.ui.onboardingDone`, re-registers the defaults,
/// publishes every key to its live consumers and logs `app.settings_reset`. Keys, the database and logs are untouched
/// (09). The dialog's text is Q-059.
struct ResetSettingsButton: View {
  let settings: TokenBeCore.Settings
  @State private var confirming = false

  var body: some View {
    Button(Strings.resetAllSettings, role: .destructive) { confirming = true }
      .accessibilityIdentifier("settings.advanced.resetAll")
      .confirmationDialog(Strings.resetAllTitle, isPresented: $confirming) {
        Button(Strings.resetConfirm, role: .destructive) { settings.resetAll() }
          .accessibilityIdentifier("settings.advanced.resetAll.confirm")
        Button(Strings.cancel, role: .cancel) {}
          .accessibilityIdentifier("settings.advanced.resetAll.cancel")
      } message: {
        Text(Strings.resetAllMessage)
      }
  }
}
