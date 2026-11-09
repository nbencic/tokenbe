import CoreGraphics
import Foundation

/// The Dashboard's saved frame (`tb.ui.dashboardFrame`, 09: `NSStringFromRect` format `{{x, y}, {w, h}}`).
/// Pure, so the app's frame keeper only reads and applies; Core has no AppKit (04).
public enum WindowFrame {
  /// `{{x, y}, {w, h}}` with integral points, as `NSStringFromRect` writes it.
  public static func encode(_ rect: CGRect) -> String {
    let rect = rect.integral
    return "{{\(Int(rect.minX)), \(Int(rect.minY))}, {\(Int(rect.width)), \(Int(rect.height))}}"
  }

  /// Parses `encode`'s format (also with decimals, as `NSStringFromRect` writes fractional frames). Nil for
  /// anything else, or for non-finite or non-positive sizes.
  public static func decode(_ text: String) -> CGRect? {
    let numbers = text.split(whereSeparator: { "{}, ".contains($0) }).compactMap { Double($0) }
    let shape = text.filter { "{},".contains($0) }
    guard numbers.count == 4, shape == "{{,},{,}}" else { return nil }
    let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    // Raw numbers, not `rect.width`: CGRect's width and height are standardized (always non-negative).
    guard numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0 else { return nil }
    return rect
  }

  /// The frame to restore: the saved one grown to `minimum` size, if at least `visibleMargin` points of it
  /// (each way) lie on one of `screens`; nil (let the system place the window) when nothing is saved, the text
  /// is invalid, or the frame would open off-screen (a display was disconnected).
  public static func restorable(saved: String, screens: [CGRect], minimum: CGSize,
                                visibleMargin: CGFloat = 40) -> CGRect? {
    guard var rect = decode(saved) else { return nil }
    rect.size.width = max(rect.width, minimum.width)
    rect.size.height = max(rect.height, minimum.height)
    let onScreen = screens.contains { screen in
      let overlap = screen.intersection(rect)
      return !overlap.isNull && overlap.width >= visibleMargin && overlap.height >= visibleMargin
    }
    return onScreen ? rect : nil
  }
}
