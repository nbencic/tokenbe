import SwiftUI
import TokenBeCore

/// Step 3 — First numbers (08): the mode, key count and currency the probe found; for an anchored account the
/// inline anchor amount (`Set anchor…`, saved as `ledger_event(kind=anchor)`) or `Skip for now`; `Launch at login`
/// (09 `tb.general.launchAtLogin`); `Done`.
struct Step3Result: View {
  let account: AccountRecord
  let probe: ProbeResult
  let settings: TokenBeCore.Settings?
  let lifecycle: AccountLifecycle?
  let done: () -> Void

  @State private var amount = ""
  @State private var anchoring = true
  @State private var savedCents: Int64?
  @State private var failed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        ProviderGlyph(provider: ProviderID(rawValue: account.provider) ?? .openai, size: 28)
        Text(Strings.firstNumbers)
          .font(.title2.weight(.semibold))
      }
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
        row(Strings.modeLabel, modeWord, id: "mode")
        row(Strings.keyCountLabel, "\(probe.discoveredKeys.count)", id: "keyCount")
        row(Strings.currencyLabel, account.currency, id: "currency")
      }
      if probe.capabilities.balanceModeDefault == .anchored {
        anchor
      }
      if let settings {
        Toggle(Strings.launchAtLogin, isOn: Binding(
          get: { settings.generalLaunchAtLogin }, set: { settings.generalLaunchAtLogin = $0 }
        ))
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("onboarding.launchAtLogin")
      }
      Spacer(minLength: 0)
      HStack {
        Spacer()
        Button(Strings.done, action: done)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("onboarding.done")
      }
    }
  }

  private var modeWord: String {
    switch probe.capabilities.balanceModeDefault {
    case .direct: Strings.modeDirect
    case .anchored: Strings.modeAnchoredWord
    case .spendOnly: Strings.modeSpendOnlyWord
    }
  }

  private func row(_ title: String, _ value: String, id: String) -> some View {
    GridRow {
      Text(title).foregroundStyle(.secondary)
      Text(value)
        .monospacedDigit()
        .accessibilityIdentifier("onboarding.result.\(id)")
    }
  }

  @ViewBuilder private var anchor: some View {
    if let savedCents {
      Text(Strings.anchorSaved(Formatters.money(
        Money(cents: savedCents, currency: Currency(rawValue: account.currency) ?? .usd), hideCents: false,
        locale: .current
      )))
      .monospacedDigit()
      .accessibilityIdentifier("onboarding.anchorSaved")
    } else if anchoring {
      VStack(alignment: .leading, spacing: 4) {
        Text(Strings.anchorAmount).font(.headline)
        HStack {
          TextField(Strings.anchorAmount, text: $amount)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(maxWidth: 160)
            .accessibilityIdentifier("onboarding.anchorAmount")
          Button(Strings.setAnchor) { save() }
            .disabled(Formatters.cents(fromInput: amount, locale: .current) == nil)
            .accessibilityIdentifier("onboarding.setAnchor")
          Button(Strings.skipForNow) { anchoring = false }
            .accessibilityIdentifier("onboarding.skipAnchor")
        }
        if failed {
          Text(Strings.anchorFailed).font(.caption).foregroundStyle(Color(.healthCritical))
        }
      }
    }
  }

  private func save() {
    guard let cents = Formatters.cents(fromInput: amount, locale: .current), let lifecycle else { return }
    Task {
      do {
        try await lifecycle.setAnchor(account, cents: cents)
        savedCents = cents
      } catch {
        failed = true
        Log.error(.uiError, cat: .ui, msg: "anchor not saved", acct: account.provider, err: error,
                  ctx: ["view": "onboarding"])
      }
    }
  }
}
