import SwiftUI

/// The menu-bar app (08). Stage 0.4: a code-drawn glyph and a placeholder popover, replaced in Stage 1.1.
@main
struct TokenBeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      Text(Strings.appName)
        .font(.headline)
        .padding()
    } label: {
      MenuBarGlyph()
    }
    .menuBarExtraStyle(.window)
  }
}
