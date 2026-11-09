import SwiftUI

/// The menu-bar app (08). The `AppModel` lives in the app delegate so startup (04) can fill it after logging.
@main
struct TokenBeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      PopoverView(model: appDelegate.model)
        .environment(\.appEnvironment, appDelegate.model.environment)
    } label: {
      MenuBarGlyph(state: appDelegate.model.glyphState)
    }
    .menuBarExtraStyle(.window)

    // 08 § Dashboard window. Opened from the popover only (footer button, ⌘D, ⌥-click); never at launch and
    // never by window restoration, so `tb.ui.dashboardFrame` is the only frame memory (Q-020).
    Window(Strings.dashboardTitle, id: DashboardView.windowID) {
      DashboardView(model: appDelegate.model)
        .environment(\.appEnvironment, appDelegate.model.environment)
    }
    .windowResizability(.contentMinSize)
    .defaultSize(DashboardView.minimumSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
  }
}
