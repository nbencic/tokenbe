import SwiftUI

/// The menu-bar app (08). The `AppModel` lives in the app delegate so startup (04) can fill it after logging.
/// Every scene takes the accent of `tb.ui.useSystemAccent`; the appearance applies app-wide (`AppModel`).
@main
struct TokenBeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      PopoverView(model: appDelegate.model)
        .environment(\.appEnvironment, appDelegate.model.environment)
        .tint(appDelegate.model.accentTint)
    } label: {
      StatusLabel(model: appDelegate.model)
    }
    .menuBarExtraStyle(.window)

    // 08 § Dashboard window. Opened from the popover (footer button, ⌘D, ⌥-click) or the global shortcut (Q-023);
    // never at launch and
    // never by window restoration, so `tb.ui.dashboardFrame` is the only frame memory (Q-020).
    Window(Strings.dashboardTitle, id: DashboardView.windowID) {
      DashboardView(model: appDelegate.model)
        .environment(\.appEnvironment, appDelegate.model.environment)
        .tint(appDelegate.model.accentTint)
    }
    .windowResizability(.contentMinSize)
    .defaultSize(DashboardView.minimumSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    // 08 § Settings. Opened from the popover footer (`Settings…`, ⌘,).
    Settings {
      SettingsView(model: appDelegate.model)
        .environment(\.appEnvironment, appDelegate.model.environment)
        .environment(\.hotKeyCenter, appDelegate.hotKeys)
        .tint(appDelegate.model.accentTint)
    }
  }
}

/// The menu-bar label: the glyph, plus the hand-over of `openWindow` to the model for the global shortcut.
private struct StatusLabel: View {
  let model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    MenuBarGlyph(state: model.glyphState)
      .onAppear {
        let open = openWindow
        model.openDashboard = { open(id: DashboardView.windowID) }
      }
  }
}
