import SwiftUI
import TokenBeCore

/// The provider glyph (Paper `LZ-0`, `14Z-0`): a filled circle with the provider's letter. 08 names no glyph assets,
/// so it is drawn, not loaded (Q-030, PM-3.3-1).
struct ProviderGlyph: View {
  let provider: ProviderID
  var size: CGFloat = 20

  var body: some View {
    Text(Self.letter(provider))
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(Color(.ground))
      .frame(width: size, height: size)
      .background(Circle().fill(Color.primary))
      .accessibilityHidden(true)
  }

  /// Paper's letters: OpenRouter is `R`, so it does not collide with OpenAI's `O`.
  static func letter(_ provider: ProviderID) -> String {
    switch provider {
    case .openai: "O"
    case .anthropic: "A"
    case .openrouter: "R"
    case .deepseek: "D"
    case .xai: "X"
    }
  }
}
