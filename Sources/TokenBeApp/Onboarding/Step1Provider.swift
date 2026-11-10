import SwiftUI
import TokenBeCore

/// Step 1 — Pick provider (08): a tile per provider this build offers (`registry.availableForOnboarding`; the others
/// are absent), each with 08's caption; a provider that already has an account is disabled with `Added`.
struct Step1Provider: View {
  let available: [ProviderID]
  let added: Set<ProviderID>
  @Binding var selection: ProviderID?
  let cancel: () -> Void
  let next: () -> Void

  private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 10)]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(Strings.whichProvider)
        .font(.title2.weight(.semibold))
      LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
        ForEach(available, id: \.self) { provider in
          tile(provider)
        }
      }
      Spacer(minLength: 0)
      HStack {
        Button(Strings.cancel, action: cancel)
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("onboarding.cancel")
        Spacer()
        Button(Strings.continueButton, action: next)
          .keyboardShortcut(.defaultAction)
          .disabled(selection == nil)
          .accessibilityIdentifier("onboarding.continue")
      }
    }
  }

  private func tile(_ provider: ProviderID) -> some View {
    let isAdded = added.contains(provider)
    let isSelected = selection == provider
    return Button {
      selection = provider
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        ProviderGlyph(provider: provider, size: 24)
        Text(provider.displayName)
          .font(.headline)
        Text(isAdded ? Strings.added : Self.caption(provider))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("onboarding.provider.\(provider.rawValue).caption")
      }
      .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
      .padding(12)
      .contentShape(RoundedRectangle(cornerRadius: 10))
      .background(RoundedRectangle(cornerRadius: 10).fill(Color(.ground)))
      .overlay(RoundedRectangle(cornerRadius: 10)
        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1))
    }
    .buttonStyle(.plain)
    .disabled(isAdded)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("onboarding.provider.\(provider.rawValue)")
  }

  /// 08 step 1's captions, one per provider.
  static func caption(_ provider: ProviderID) -> String {
    switch provider {
    case .openai: Strings.captionOpenAI
    case .anthropic: Strings.captionAnthropic
    case .openrouter: Strings.captionOpenRouter
    case .deepseek, .xai: Strings.captionBalanceOnly
    }
  }
}
