import AppKit
import SwiftUI
import TokenBeCore

/// Restores and saves the hosting SwiftUI window's frame in `tb.ui.dashboardFrame` (09; 14 § 1.2: saved on
/// move/resize, debounced 500 ms). It only reads and sets the frame of the window SwiftUI created; it creates
/// no AppKit window (04, Q-020). The rules (format, minimum size, off-screen check) live in Core `WindowFrame`.
struct WindowFrameKeeper: NSViewRepresentable {
  let settings: TokenBeCore.Settings?
  let minimum: CGSize

  func makeNSView(context: Context) -> KeeperView {
    KeeperView(settings: settings, minimum: minimum)
  }

  func updateNSView(_ view: KeeperView, context: Context) {}

  final class KeeperView: NSView {
    private let settings: TokenBeCore.Settings?
    private let minimum: CGSize
    private let debouncer = Debouncer(delay: .milliseconds(500), clock: ContinuousClock())
    private var observers: [NSObjectProtocol] = []

    init(settings: TokenBeCore.Settings?, minimum: CGSize) {
      self.settings = settings
      self.minimum = minimum
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // Leaving the window (close) also arrives here with `window == nil`: the observers go with it.
      observers.forEach(NotificationCenter.default.removeObserver)
      observers = []
      guard let window, let settings else { return }
      let screens = NSScreen.screens.map(\.visibleFrame)
      if let frame = WindowFrame.restorable(saved: settings.uiDashboardFrame, screens: screens, minimum: minimum) {
        window.setFrame(frame, display: true)
      }
      for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
        let token = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.scheduleSave() }
        }
        observers.append(token)
      }
      observers.append(NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification, object: window, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.saveNow() } })
    }

    private func scheduleSave() {
      debouncer.submit { [weak self] in self?.saveNow() }
    }

    private func saveNow() {
      debouncer.cancel()
      guard let window, let settings else { return }
      settings.uiDashboardFrame = WindowFrame.encode(window.frame)
    }
  }
}
