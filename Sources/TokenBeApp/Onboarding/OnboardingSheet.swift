import SwiftUI
import TokenBeCore

/// Onboarding (08 § Onboarding; Paper `LZ-0`, `I4-0`, `JV-0`; 520×440). A menu-bar app has no window to carry a
/// sheet, so it is its own fixed-size window (Q-030). Step 2 creates the account once the probe passes; step 3
/// shows what the probe found, takes the optional anchor, and `Done` starts the first polls.
struct OnboardingSheet: View {
  static let windowID = "onboarding"
  static let size = CGSize(width: 520, height: 440)

  let model: AppModel
  @State private var flow = OnboardingFlow()
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StepHeader(step: flow.step)
        .padding(.bottom, 16)
      switch flow.step {
      case .provider:
        Step1Provider(available: environment?.registry.availableForOnboarding ?? [],
                      added: Set(model.accounts.map(\.provider)), selection: $flow.provider,
                      cancel: close, next: { flow.step = .key })
      case .key:
        if let provider = flow.provider {
          Step2Key(provider: provider, label: $flow.label, actionTitle: Strings.testAndContinue,
                   back: { flow.step = .provider }, cancel: close,
                   submit: { key in await create(provider, key: key) })
        }
      case .result:
        if let created = flow.created {
          Step3Result(account: created.account, probe: created.probe, settings: environment?.settings,
                      lifecycle: environment?.lifecycle, done: finish)
        }
      }
    }
    .padding(24)
    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("onboarding.root")
    .onDisappear { flow = OnboardingFlow() }
  }

  /// `Test & continue`: the probe, then on success the Keychain item, the account and its rows (14 § Stage 3.5
  /// step 1). Returns the message to show, or nil when step 3 follows.
  private func create(_ provider: ProviderID, key: String) async -> String? {
    guard let lifecycle = environment?.lifecycle else { return Strings.accountCreateFailed }
    let probe = await lifecycle.probe(provider, key: key)
    if let message = probe.humanMessage { return message }
    do {
      let account = try await lifecycle.create(provider, label: flow.label, key: key, probe: probe)
      environment?.settings.uiOnboardingDone = true
      model.missingKeys.remove(account.keychainRef)
      flow.created = OnboardingFlow.Created(account: account, probe: probe)
      flow.step = .result
      return nil
    } catch {
      Log.error(.uiError, cat: .ui, msg: "account not created", acct: provider.rawValue, err: error,
                ctx: ["view": "onboarding"])
      return Strings.accountCreateFailed
    }
  }

  /// `Done`: closes and starts the first `keys` and `usage` polls, fire-and-forget; the poller logs them (3.4).
  private func finish() {
    if let account = flow.created?.account, let poller = environment?.poller {
      Task {
        _ = await poller.runOnce(account: account, job: .keys)
        _ = await poller.runOnce(account: account, job: .usage)
      }
    }
    close()
  }

  private func close() {
    dismissWindow(id: Self.windowID)
  }
}

/// Where onboarding is; never holds the key (R8: the key lives only in step 2's field until it is stored).
@Observable @MainActor
final class OnboardingFlow {
  enum Step { case provider, key, result }

  struct Created {
    var account: AccountRecord
    var probe: ProbeResult
  }

  var step = Step.provider
  var provider: ProviderID? {
    didSet { if provider != oldValue { label = provider?.displayName ?? "" } }
  }
  var label = ""
  var created: Created?
}

/// `Provider — Key — Balance` (Paper).
private struct StepHeader: View {
  let step: OnboardingFlow.Step

  var body: some View {
    HStack(spacing: 8) {
      item(Strings.stepProvider, current: step == .provider)
      rule
      item(Strings.stepKey, current: step == .key)
      rule
      item(Strings.stepResult, current: step == .result)
    }
    .font(.caption)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("onboarding.steps")
  }

  private var rule: some View {
    Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 14, height: 1)
  }

  private func item(_ title: String, current: Bool) -> some View {
    Text(title)
      .fontWeight(current ? .semibold : .regular)
      .foregroundStyle(current ? Color.primary : Color.secondary)
  }
}
