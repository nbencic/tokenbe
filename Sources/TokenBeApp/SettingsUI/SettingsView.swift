import SwiftUI
import TokenBeCore

/// The `Settings` scene (08 § Settings): one tab per area that exists so far, in Paper's order. Sources (4.1) and
/// Alerts (5.3) join with their stages. Every control is bound to a 09 key through `Settings`; Accounts edits
/// `account` rows (3.5). The selected tab lives on the model, so `Key missing · Fix…` can open Accounts.
struct SettingsView: View {
  @Bindable var model: AppModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Group {
      if let environment = model.environment {
        TabView(selection: $model.settingsTab) {
          Tab(Strings.tabGeneral, systemImage: "gearshape", value: SettingsTab.general) {
            GeneralTab(settings: environment.settings)
          }
          Tab(Strings.tabAccounts, systemImage: "person.crop.rectangle.stack", value: SettingsTab.accounts) {
            AccountsTab(model: model, environment: environment)
          }
          Tab(Strings.tabPrivacy, systemImage: "hand.raised", value: SettingsTab.privacy) {
            PrivacyTab(logsDirectory: environment.logsDirectory)
          }
          Tab(Strings.tabAdvanced, systemImage: "wrench.and.screwdriver", value: SettingsTab.advanced) {
            AdvancedTab(settings: environment.settings, logsDirectory: environment.logsDirectory,
                        repository: environment.repository)
          }
        }
      } else {
        ProgressView()
      }
    }
    // Paper's Accounts tab is master-detail at 720 pt; the form tabs keep 520 pt.
    .frame(width: model.settingsTab == .accounts ? 720 : 520)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.root")
    // The effective appearance, for the UI test that flips `tb.ui.appearance` (14 § Stage 1.3 Tests).
    .accessibilityValue(colorScheme == .dark ? "dark" : "light")
  }
}

/// `Open log folder` (Privacy and Advanced tabs): reveals the NDJSON log directory (07) in Finder.
struct OpenLogFolderButton: View {
  let logsDirectory: URL

  var body: some View {
    Button(Strings.openLogFolder) {
      NSWorkspace.shared.open(logsDirectory)
    }
  }
}
