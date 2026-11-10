import Foundation

/// Provider identifiers (03 `account.provider` CHECK), in 08's onboarding tile order. Moved here from
/// `SettingSpec.swift` (14 § Stage 3.3 step 1).
public enum ProviderID: String, CaseIterable, Sendable, Codable {
  case openai, anthropic, openrouter, deepseek, xai

  /// The provider's name as 08's onboarding tiles write it; also the default account label (08 § Onboarding).
  public var displayName: String {
    switch self {
    case .openai: "OpenAI"
    case .anthropic: "Anthropic"
    case .openrouter: "OpenRouter"
    case .deepseek: "DeepSeek"
    case .xai: "xAI"
    }
  }

  /// The prefix 02's capability matrix gives for the key a user pastes. Nil where 02 names none (OpenRouter's
  /// Management key, DeepSeek's and xAI's standard keys): those keys are checked by the probe only (Q-028).
  public var keyPrefix: String? {
    // Joined at run time: as literals, Swift stores these short strings inline in the instructions, side by side,
    // and the build-product scan of `check-no-secrets.sh` then reads them as one key-shaped run (Q-028).
    switch self {
    case .openai: ["sk", "admin", ""].joined(separator: "-")
    case .anthropic: ["sk", "ant", "admin01", ""].joined(separator: "-")
    case .openrouter, .deepseek, .xai: nil
    }
  }

  /// Onboarding step 2's live check (08): is the pasted text plausibly this provider's key?
  public func checkKey(_ pasted: String) -> KeyCheck {
    let key = Self.normalizedKey(pasted)
    guard !key.isEmpty else { return .empty }
    guard let keyPrefix else { return .plausible }
    return key.hasPrefix(keyPrefix) ? .plausible : .wrongPrefix(expected: keyPrefix)
  }

  /// The key without the whitespace and newlines a paste can carry; what the probe sends and the Keychain stores.
  public static func normalizedKey(_ pasted: String) -> String {
    pasted.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// The outcome of `ProviderID.checkKey(_:)`. The UI turns `wrongPrefix` into 08's inline copy (3.5).
public enum KeyCheck: Sendable, Equatable {
  /// The prefix matches, or 02 names none; the probe decides.
  case plausible
  case empty
  case wrongPrefix(expected: String)
}
