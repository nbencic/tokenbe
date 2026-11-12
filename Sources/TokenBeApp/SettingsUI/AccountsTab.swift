import SwiftUI
import TokenBeCore

/// Settings → Accounts (08 § Settings, Paper `14Z-0`; 14 § Stage 3.5 step 2): the account list (184 pt) and the
/// selected account's label, key status, `Replace key…`, `Test`, `Remove account…`, `Paused`, the refresh-interval
/// overrides (09 `account.interval_override_json`, 14 § Stage 4.1) and Keys & apps.
struct AccountsTab: View {
  let model: AppModel
  let environment: AppEnvironment
  @State private var selectedID: String?

  var body: some View {
    HStack(spacing: 0) {
      List(selection: $selectedID) {
        ForEach(model.records, id: \.id) { record in
          HStack(spacing: 8) {
            ProviderGlyph(provider: ProviderID(rawValue: record.provider) ?? .openai, size: 18)
            Text(record.label)
          }
          .tag(record.id)
          .accessibilityIdentifier("settings.accounts.row.\(record.provider)")
        }
      }
      .frame(width: 184)
      .accessibilityIdentifier("settings.accounts.list")
      Divider()
      Group {
        if let record = model.records.first(where: { $0.id == selectedID }) {
          AccountDetail(record: record, summary: model.accounts.first { $0.id == record.id }, model: model,
                        environment: environment)
            .id(record.id)
        } else {
          Text(Strings.noAccountSelected)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(minHeight: 420)
    .onAppear { if selectedID == nil { selectedID = model.records.first?.id } }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.accounts")
  }
}

/// One account's controls. Every write goes through `Repository`/`AccountLifecycle`; failures log `ui.error`.
private struct AccountDetail: View {
  let record: AccountRecord
  let summary: AccountSummary?
  let model: AppModel
  let environment: AppEnvironment

  @State private var label = ""
  @State private var keys: [ProviderKeyRecord] = []
  @State private var testing = false
  @State private var testMessage: String?
  @State private var testedAt: Date?
  @State private var replacing = false
  @State private var confirmingRemove = false

  private var provider: ProviderID { ProviderID(rawValue: record.provider) ?? .openai }

  var body: some View {
    Form {
      Section {
        HStack(spacing: 10) {
          ProviderGlyph(provider: provider, size: 28)
          TextField(Strings.accountLabel, text: $label)
            .textFieldStyle(.roundedBorder)
            .onSubmit { saveLabel() }
            .accessibilityIdentifier("settings.accounts.label")
        }
      }
      Section {
        HStack {
          Text(statusLine)
            .foregroundStyle(summary?.needsKey == true ? Color(.healthLow) : Color.secondary)
            .accessibilityIdentifier("settings.accounts.keyStatus")
          Spacer()
          if testing { ProgressView().controlSize(.small) }
          Button(Strings.replaceKey) { replacing = true }
            .accessibilityIdentifier("settings.accounts.replaceKey")
          Button(Strings.test) { test() }
            .disabled(testing)
            .accessibilityIdentifier("settings.accounts.test")
        }
        if let testMessage {
          Text(testMessage)
            .font(.callout)
            .foregroundStyle(Color(.healthCritical))
            .accessibilityIdentifier("settings.accounts.testMessage")
        }
        Toggle(Strings.paused, isOn: Binding(get: { record.paused }, set: { setPaused($0) }))
          .accessibilityIdentifier("settings.accounts.paused")
      }
      if !overridableJobs.isEmpty {
        Section {
          IntervalOverrides(record: record, provider: provider, jobs: overridableJobs,
                            settings: environment.settings) { json in
            update { $0.intervalOverrideJson = json }
          }
        }
      }
      Section(Strings.keysAndApps) {
        if keys.isEmpty {
          Text(Strings.noKeysYet).foregroundStyle(.secondary)
        } else {
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
              Text(Strings.keyName).font(.caption).foregroundStyle(.secondary)
              Text(Strings.keyHint).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(keys, id: \.providerKeyId) { key in
              GridRow {
                Text(key.name ?? Strings.unnamedKey)
                Text(Self.hint(key.redacted)).monospaced()
              }
              .accessibilityElement(children: .combine)
              .accessibilityIdentifier("settings.accounts.key.\(key.providerKeyId)")
            }
          }
        }
      }
      Section {
        HStack {
          Spacer()
          Button(Strings.removeAccount, role: .destructive) { confirmingRemove = true }
            .accessibilityIdentifier("settings.accounts.remove")
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      label = record.label
      Task { await loadKeys() }
    }
    .onDisappear { saveLabel() }
    .sheet(isPresented: $replacing) {
      Step2Key(provider: provider, actionTitle: Strings.testAndContinue, cancel: { replacing = false },
               submit: { key in await replace(key) })
      .padding(24)
      .frame(width: OnboardingSheet.size.width, height: 320)
    }
    .confirmationDialog(Strings.removeAccountQuestion(record.label), isPresented: $confirmingRemove) {
      Button(Strings.remove, role: .destructive) { remove() }
        .accessibilityIdentifier("settings.accounts.confirmRemove")
      Button(Strings.cancel, role: .cancel) {}
    } message: {
      Text(Strings.removeAccountDetail)
    }
  }

  /// The minute-cadence jobs this account runs (its capabilities, and a 09 interval for its provider).
  private var overridableJobs: [Job] {
    // An unreadable row runs no jobs; the coordinator logs it once (`poll.failed`), so a render does not.
    guard case .success(let capabilities) = Result(catching: { try Capabilities.decode(json: record.capabilities) })
    else { return [] }
    return Job.minuteCadence.filter { $0.applies(to: capabilities) && $0.intervalKey(for: provider) != nil }
  }

  /// `Valid · tested <freshness>`: the last passed probe (creation, `Test`) or successful poll (08).
  private var statusLine: String {
    if summary?.needsKey == true { return Strings.keyMissing }
    let tested = [testedAt, summary?.lastSuccessAt, DBTime.date(record.createdAt)].compactMap { $0 }.max()
    return Strings.keyValid(Formatters.freshness(tested, now: Date(), calendar: .current))
  }

  /// `…a1b2`: the last 4 characters of the provider's redacted value (03 key hint).
  static func hint(_ redacted: String?) -> String {
    guard let redacted, redacted.count >= 4 else { return "\u{2014}" }
    return Strings.hint(String(redacted.suffix(4)))
  }

  private func loadKeys() async {
    guard let repository = environment.repository else { return }
    do {
      keys = try await repository.fetchProviderKeys(accountID: record.id)
    } catch {
      report(error, "keys not loaded")
    }
  }

  private func saveLabel() {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != record.label else { return }
    update { $0.label = trimmed }
  }

  private func setPaused(_ paused: Bool) {
    update { $0.paused = paused }
  }

  private func update(_ change: (inout AccountRecord) -> Void) {
    guard let repository = environment.repository else { return }
    var changed = record
    change(&changed)
    let updated = changed
    Task {
      do {
        try await repository.updateAccount(updated)
      } catch {
        report(error, "account not updated")
      }
    }
  }

  private func test() {
    guard let lifecycle = environment.lifecycle else { return }
    testing = true
    testMessage = nil
    Task {
      let result = await lifecycle.test(record)
      testing = false
      testMessage = result.humanMessage
      if result.humanMessage == nil { testedAt = Date() }
    }
  }

  private func replace(_ key: String) async -> String? {
    guard let lifecycle = environment.lifecycle else { return Strings.keyReplaceFailed }
    let probe = await lifecycle.probe(provider, key: key)
    if let message = probe.humanMessage { return message }
    do {
      try await lifecycle.replaceKey(record, key: key, probe: probe)
      model.missingKeys.remove(record.keychainRef)
      testedAt = Date()
      testMessage = nil
      replacing = false
      await loadKeys()
      return nil
    } catch {
      report(error, "key not replaced")
      return Strings.keyReplaceFailed
    }
  }

  private func remove() {
    guard let lifecycle = environment.lifecycle else { return }
    let coordinator = environment.coordinator
    Task {
      // Its polls stop first, so none reads the key while it is being deleted (Q-034).
      await coordinator?.stop(record.id)
      do {
        try await lifecycle.remove(record, settings: environment.settings)
        model.missingKeys.remove(record.keychainRef)
      } catch {
        report(error, "account not removed")
      }
    }
  }

  private func report(_ error: any Error, _ msg: String) {
    Log.error(.uiError, cat: .ui, msg: msg, acct: record.provider, err: error, ctx: ["view": "settings.accounts"])
  }
}

/// 09 `account.interval_override_json` (14 § Stage 4.1 Inventory): per job, the Sources setting or this account's
/// own period, within the same 09 range (Q-034).
private struct IntervalOverrides: View {
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
