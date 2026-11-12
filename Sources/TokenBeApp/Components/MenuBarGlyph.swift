import AppKit
import SwiftUI

/// The glyph's three shapes (08 § Menu bar glyph). Colour is never used in the menu bar; the shape carries the state.
enum GlyphState: String, CaseIterable {
  /// All accounts healthy or watch.
  case solid
  /// Any account low or critical.
  case notched
  /// Any account stale, or offline.
  case dashed
}

/// An 18 pt template image with a 1.5 pt ring (O-2), drawn in code. Menu-bar labels render images, not SwiftUI
/// shapes, so each state is drawn once into an `NSImage`.
struct MenuBarGlyph: View {
  static let size = CGSize(width: 18, height: 18)
  static let lineWidth: CGFloat = 1.5

  let state: GlyphState

  var body: some View {
    Image(nsImage: Self.image(for: state))
      .accessibilityLabel(Strings.appName)
      // The shape, for VoiceOver and the UI tests (`glyph.dashed`, 14 § Stage 4.2).
      .accessibilityValue(state.rawValue)
      .accessibilityIdentifier("glyph.\(state.rawValue)")
  }

  static func image(for state: GlyphState) -> NSImage {
    switch state {
    case .solid: solid
    case .notched: notched
    case .dashed: dashed
    }
  }

  private static let solid = draw { rect in
    NSBezierPath(ovalIn: rect)
  }

  /// The ring with a 50° gap at the top.
  private static let notched = draw { rect in
    let path = NSBezierPath()
    path.appendArc(
      withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: 115, endAngle: 65,
      clockwise: false
    )
    return path
  }

  private static let dashed = draw { rect in
    let path = NSBezierPath(ovalIn: rect)
    path.setLineDash([2.2, 1.8], count: 2, phase: 0)
    return path
  }

  private static func draw(_ shape: @escaping (NSRect) -> NSBezierPath) -> NSImage {
    let image = NSImage(size: size, flipped: false) { bounds in
      let inset = lineWidth / 2 + 2
      let path = shape(bounds.insetBy(dx: inset, dy: inset))
      path.lineWidth = lineWidth
      NSColor.black.setStroke()
      path.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }
}
