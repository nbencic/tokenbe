import SwiftUI
import TokenBeCore

/// Settings → Sources (08 § Settings, Paper `YP-0`; 14 § Stage 4.1 step 3): the minute-cadence intervals and the
/// Low Power multiplier (09 § Sources). Each change reaches the coordinator through `Settings.changes`.
/// `Run daily tasks now` (4.3) runs the daily activity out of band (04). Harness reports (7.2) and Price book (5.1)
/// join with their stages.
struct SourcesTab: View {
  @Bindable var settings: TokenBeCore.Settings
  /// Nil only when startup did not reach step 7 (the database failed, and the app quits).
  let daily: DailyActivityRegistration?

  var body: some View {
    Form {
      Section {
        IntervalStepper(label: Strings.balanceEvery, value: $settings.pollBalanceIntervalS,
                        key: .pollBalanceIntervalS, step: 30, identifier: "settings.sources.balance")
        IntervalStepper(label: Strings.anthropicUsageEvery, value: $settings.pollUsageIntervalAnthropicS,
                        key: .pollUsageIntervalAnthropicS, step: 60, identifier: "settings.sources.usageAnthropic")
        IntervalStepper(label: Strings.openAIUsageEvery, value: $settings.pollUsageIntervalOpenAIS,
                        key: .pollUsageIntervalOpenAIS, step: 60, identifier: "settings.sources.usageOpenAI")
        IntervalStepper(label: Strings.keysEvery, value: $settings.pollKeysIntervalS,
                        key: .pollKeysIntervalS, step: 600, identifier: "settings.sources.keys")
      }
      Section {
        Stepper(value: $settings.pollLowPowerMultiplier,
                in: SettingsKey.pollLowPowerMultiplier.spec.intBounds ?? 1...10) {
          LabeledContent(Strings.lowPowerMultiplier, value: Strings.times(settings.pollLowPowerMultiplier))
        }
        .accessibilityIdentifier("settings.sources.lowPower")
        Text(Strings.lowPowerCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let daily {
        Section {
          HStack {
            Button(Strings.runDailyTasksNow) {
              Task { await daily.run() }
            }
            .disabled(daily.isRunning)
            .accessibilityIdentifier("settings.sources.runDaily")
            if daily.isRunning {
              ProgressView()
                .controlSize(.small)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}

/// One period in seconds, stepped within its 09 range (Q-034: steps of 30 s, 1 min or 10 min).
struct IntervalStepper: View {
  let label: String
  @Binding var value: Int
  let key: SettingsKey
  let step: Int
  let identifier: String

  var body: some View {
    Stepper(value: $value, in: key.spec.intBounds ?? 60...3600, step: step) {
      LabeledContent(label, value: Formatters.interval(seconds: value))
    }
    .accessibilityIdentifier(identifier)
  }
}
