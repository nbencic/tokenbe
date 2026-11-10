import AppKit
import SwiftUI
import TokenBeCore

/// Step 2 — Paste key (08), also the body of `Replace key…` (14 § Stage 3.5 step 2, without the label field).
/// A secure field with `Paste`, live prefix validation, and the action button running the probe with a spinner;
/// a failure shows the probe's human message, never raw JSON. The key exists only in this view's state and is
/// cleared as soon as it has been handed on (R8).
struct Step2Key: View {
  let provider: ProviderID
  /// Nil hides the label field (`Replace key…`).
  var label: Binding<String>?
  let actionTitle: String
  var back: (() -> Void)?
  let cancel: () -> Void
  /// Runs the probe (and, on success, the writes); returns the message to show, or nil when done.
  let submit: (String) async -> String?

  @State private var key = ""
  @State private var message: String?
  @State private var testing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        ProviderGlyph(provider: provider, size: 28)
        Text(Strings.keyTitle(provider.displayName))
          .font(.title2.weight(.semibold))
      }
      if let label {
        VStack(alignment: .leading, spacing: 4) {
          Text(Strings.accountLabel).font(.headline)
          TextField(Strings.accountLabel, text: label)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("onboarding.label")
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(Strings.apiKeyLabel).font(.headline)
        HStack {
          SecureField(Strings.apiKeyLabel, text: $key)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("onboarding.key")
          Button(Strings.paste) {
            key = NSPasteboard.general.string(forType: .string) ?? key
          }
          .accessibilityIdentifier("onboarding.paste")
        }
        if let prefixMessage {
          Text(prefixMessage)
            .font(.caption)
            .foregroundStyle(Color(.healthLow))
            .accessibilityIdentifier("onboarding.prefixMessage")
        } else {
          Text(Strings.keychainNote)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      if let message {
        Text(message)
          .font(.callout)
          .foregroundStyle(Color(.healthCritical))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("onboarding.probeMessage")
      }
      Spacer(minLength: 0)
      HStack {
        Button(Strings.cancel, action: cancel)
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("onboarding.cancel")
        Spacer()
        if testing {
          ProgressView().controlSize(.small)
            .accessibilityIdentifier("onboarding.spinner")
        }
        if let back {
          Button(Strings.back, action: back)
            .disabled(testing)
            .accessibilityIdentifier("onboarding.back")
        }
        Button(actionTitle) { run() }
          .keyboardShortcut(.defaultAction)
          .disabled(testing || provider.checkKey(key) != .plausible)
          .accessibilityIdentifier("onboarding.test")
      }
    }
    .onDisappear { key = "" }
  }

  /// 08's live validation: only a wrong prefix speaks; an empty field stays quiet.
  private var prefixMessage: String? {
    guard case .wrongPrefix(let expected) = provider.checkKey(key) else { return nil }
    return provider == .openai ? Strings.wrongPrefixOpenAI : Strings.wrongPrefix(expected)
  }

  private func run() {
    let typed = key
    testing = true
    message = nil
    Task {
      let result = await submit(typed)
      testing = false
      message = result
      if result == nil { key = "" }
    }
  }
}
