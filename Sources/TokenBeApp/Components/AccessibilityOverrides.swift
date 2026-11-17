import SwiftUI

/// 08 § Accessibility in the popover: text sizes up to `xxLarge` (larger sizes are capped there, so the 360 pt
/// popover keeps its layout), and Reduce Motion (`ReduceMotion`). DEBUG UI tests under `TOKENBE_TEST_ROOT` stand in
/// for the system settings, which a test never changes on the owner's Mac: `TOKENBE_TEST_TEXT_SIZE=xxLarge` sets the
/// popover's text size and `TOKENBE_TEST_REDUCE_MOTION=1` turns Reduce Motion on (Q-054).
enum AccessibilityOverrides {
  static let textSizeVariable = "TOKENBE_TEST_TEXT_SIZE"
  static let reduceMotionVariable = "TOKENBE_TEST_REDUCE_MOTION"

  /// The test's text size; nil outside a DEBUG test root.
  static var textSize: DynamicTypeSize? {
    #if DEBUG
    guard testRoot, let name = environment[textSizeVariable] else { return nil }
    return DynamicTypeSize.allCases.first { "\($0)" == name }
    #else
    return nil
    #endif
  }

  /// Reduce Motion forced on by a DEBUG UI test.
  static var reduceMotion: Bool {
    #if DEBUG
    return testRoot && environment[reduceMotionVariable] == "1"
    #else
    return false
    #endif
  }

  private static var environment: [String: String] { ProcessInfo.processInfo.environment }
  private static var testRoot: Bool { environment[Startup.testRootVariable] != nil }
}

/// The popover's text size: the system's (or a DEBUG test's), never above `xxLarge` (08).
struct PopoverTextSize: ViewModifier {
  func body(content: Content) -> some View {
    if let size = AccessibilityOverrides.textSize {
      // The inner range wins over the outer value, so a size above `xxLarge` is capped too.
      content.dynamicTypeSize(...DynamicTypeSize.xxLarge).dynamicTypeSize(size)
    } else {
      content.dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
  }
}

/// A card font that follows the text size. macOS keeps a text style's point size at every `dynamicTypeSize` (the 8.4
/// probe measured 26 pt at `large` and at `xxLarge`), so the popover's cards scale their own points by the size's
/// ratio to `large` (iOS body points: 14, 15, 16, 17, 19, 21, 23 for xSmall…xxxLarge; Q-054).
struct ScaledFont: ViewModifier {
  @Environment(\.dynamicTypeSize) private var size
  let points: CGFloat
  var weight: Font.Weight = .regular
  var monospacedDigits = false

  func body(content: Content) -> some View {
    let font = Font.system(size: (points * Self.scale(size)).rounded(), weight: weight)
    content.font(monospacedDigits ? font.monospacedDigit() : font)
  }

  static func scale(_ size: DynamicTypeSize) -> CGFloat {
    switch size {
    case .xSmall: 14 / 17
    case .small: 15 / 17
    case .medium: 16 / 17
    case .large: 1
    case .xLarge: 19 / 17
    default: 21 / 17  // xxLarge, and every larger size capped to it (08)
    }
  }
}

extension View {
  /// `points` at the default text size, scaled with the popover's text size (08 § Accessibility, `ScaledFont`).
  func scaledFont(_ points: CGFloat, weight: Font.Weight = .regular, monospacedDigits: Bool = false) -> some View {
    modifier(ScaledFont(points: points, weight: weight, monospacedDigits: monospacedDigits))
  }
}

/// Reduce Motion (08 § Accessibility): the system setting, or a DEBUG UI test's override.
struct ReduceMotion {
  let system: Bool
  var isOn: Bool { system || AccessibilityOverrides.reduceMotion }
}

/// A spinner that follows Reduce Motion (08: no rotation; an opacity pulse instead).
struct BusyIndicator: View {
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  var small = false

  var body: some View {
    if ReduceMotion(system: systemReduceMotion).isOn {
      Image(systemName: "circle.fill")
        .font(small ? .caption2 : .caption)
        .foregroundStyle(.secondary)
        .symbolEffect(.pulse, options: .repeat(.continuous))
        .accessibilityLabel(Strings.busy)
        .accessibilityIdentifier("busy.pulse")
    } else {
      ProgressView().controlSize(small ? .small : .regular)
    }
  }
}
