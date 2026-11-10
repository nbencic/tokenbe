import SwiftUI
import TokenBeCore

/// The `Settings` scene (08 § Settings): one tab per area that exists so far. Accounts (3.5), Sources (4.1) and
/// Alerts (5.3) join with their stages. Every control is bound to a 09 key through `Settings`.
struct SettingsView: View {
  let model: AppModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Group {
      if let environment = model.environment {
        TabView {
          Tab(Strings.tabGeneral, systemImage: "gearshape") {
            GeneralTab(settings: environment.settings)
          }
          Tab(Strings.tabPrivacy, systemImage: "hand.raised") {
            PrivacyTab(logsDirectory: environment.logsDirectory)
          }
          Tab(Strings.tabAdvanced, systemImage: "wrench.and.screwdriver") {
            AdvancedTab(settings: environment.settings, logsDirectory: environment.logsDirectory)
          }
        }
      } else {
        ProgressView()
      }
    }
    .frame(width: 520)
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
