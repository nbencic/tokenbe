import AppKit
import SwiftUI

/// The menu-bar glyph (08, O-2): a 1.5 pt ring in an 18 pt template image, drawn in code so it follows the
/// menu bar's light/dark rendering. The dashed and alert variants arrive with the glyph states in Stage 1.1/5.5.
struct MenuBarGlyph: View {
  static let size = CGSize(width: 18, height: 18)
  static let lineWidth: CGFloat = 1.5

  var body: some View {
    Image(nsImage: Self.ring)
      .accessibilityLabel(Strings.appName)
  }

  /// Menu-bar labels render images, not arbitrary shapes, so the ring is drawn into a template `NSImage`.
  static let ring: NSImage = {
    let image = NSImage(size: size, flipped: false) { rect in
      let inset = lineWidth / 2 + 2
      let path = NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))
      path.lineWidth = lineWidth
      NSColor.black.setStroke()
      path.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }()
}
