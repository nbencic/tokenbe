import SwiftUI
import TokenBeCore

/// 09 `account.interval_override_json` (14 § Stage 4.1 Inventory): per job, the Sources setting or this account's
/// own period, within the same 09 range (Q-034).
struct IntervalOverrides: View {
  let record: AccountRecord
  let provider: ProviderID
  let jobs: [Job]
  let settings: TokenBeCore.Settings
  let save: (String?) -> Void
  @State private var expanded = false

  private var current: IntervalOverride {
    IntervalOverride.parse(record.intervalOverrideJson, provider: provider).override
  }

  var body: some View {
    DisclosureGroup(Strings.refreshIntervals, isExpanded: $expanded) {
      ForEach(jobs, id: \.self) { job in
        row(job)
      }
    }
    .accessibilityIdentifier("settings.accounts.intervals")
  }

  @ViewBuilder private func row(_ job: Job) -> some View {
    let global = globalSeconds(job)
    Toggle(Self.label(job), isOn: Binding(
      get: { current.seconds[job] != nil },
      set: { set(job, $0 ? global : nil) }
    ))
    .accessibilityIdentifier("settings.accounts.override.\(job.rawValue)")
    if let value = current.seconds[job], let bounds = job.overrideBounds(for: provider) {
      Stepper(value: Binding(get: { value }, set: { set(job, $0) }), in: bounds, step: Self.step(job)) {
        LabeledContent(Self.label(job), value: Formatters.interval(seconds: value))
      }
      .accessibilityIdentifier("settings.accounts.override.\(job.rawValue).value")
    } else {
      Text(Strings.sourcesDefault(Formatters.interval(seconds: global)))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func set(_ job: Job, _ seconds: Int?) {
    var next = current
    next.seconds[job] = seconds
    save(next.json())
  }

  private func globalSeconds(_ job: Job) -> Int {
    let interval = job.interval(for: provider, settings: ScheduleSettings(settings), override: IntervalOverride(),
                                lowPower: false)
    return Int(interval?.components.seconds ?? 0)
  }

  static func label(_ job: Job) -> String {
    switch job {
    case .usage: Strings.usageEvery
    case .balance: Strings.balanceEvery
    case .keys, .cost: Strings.keysEvery
    }
  }

  static func step(_ job: Job) -> Int {
    switch job {
    case .balance: 30
    case .usage: 60
    case .keys, .cost: 600
    }
  }
}
