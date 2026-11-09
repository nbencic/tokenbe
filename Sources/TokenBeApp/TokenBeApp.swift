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
  }
}
