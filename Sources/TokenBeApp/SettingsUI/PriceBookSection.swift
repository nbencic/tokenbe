import SwiftUI
import TokenBeCore

/// Settings → Sources → **Price book** (08 § Settings; Paper `10V-0`; 14 § Stage 5.1 step 6): the feed toggle with
/// the snapshot line and `Refresh now`, the staleness threshold (09 `tb.price.staleAfterDays`), and the overrides
/// table (model, input/output/cache rates in USD per 1M tokens) with `+`/`−` and `Reset to feed` (Q-038).
struct PriceBookSection: View {
  @Bindable var settings: TokenBeCore.Settings
  let prices: PriceBookModel
  @State private var selection: String?
  @State private var adding = false
  @State private var confirmingReset = false

  var body: some View {
    Section(Strings.priceBook) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(Strings.priceFeedTitle)
          TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(caption(now: context.date))
              .font(.caption)
              .foregroundStyle(prices.status.isStale ? Color(.healthWatch) : .secondary)
              .accessibilityIdentifier("settings.sources.priceSnapshot")
          }
        }
        Spacer(minLength: 0)
        Button(Strings.refreshNow) {
          Task { await prices.refreshNow() }
        }
        .controlSize(.small)
        .disabled(!settings.priceFeedEnabled || prices.isRefreshing)
        .accessibilityIdentifier("settings.sources.priceRefresh")
        Toggle(Strings.priceFeedToggle, isOn: $settings.priceFeedEnabled)
          .toggleStyle(.switch)
          .labelsHidden()
          .accessibilityIdentifier("settings.sources.priceFeed")
      }
      Stepper(value: $settings.priceStaleAfterDays, in: SettingsKey.priceStaleAfterDays.spec.intBounds ?? 1...60) {
        LabeledContent(Strings.priceStaleAfter, value: Strings.days(settings.priceStaleAfterDays))
      }
      .accessibilityIdentifier("settings.sources.priceStaleAfter")
    }
    Section {
      VStack(alignment: .leading, spacing: 2) {
        Text(Strings.priceOverridesTitle)
        Text(Strings.priceOverridesCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      overridesTable
      HStack(spacing: 6) {
        Button {
          adding = true
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel(Strings.priceAddOverride)
        .accessibilityIdentifier("settings.sources.priceAdd")
        Button {
          if let model = selection {
            selection = nil
            Task { await prices.removeOverride(model: model) }
          }
        } label: {
          Image(systemName: "minus")
        }
        .disabled(selection == nil)
        .accessibilityLabel(Strings.priceRemoveOverride)
        .accessibilityIdentifier("settings.sources.priceRemove")
        Spacer()
        Button(Strings.resetToFeed) {
          confirmingReset = true
        }
        .disabled(prices.status.overrides.isEmpty)
        .accessibilityIdentifier("settings.sources.priceReset")
      }
      .controlSize(.small)
    }
    .sheet(isPresented: $adding) {
      OverrideSheet(prices: prices)
    }
    .confirmationDialog(Strings.resetToFeedConfirm, isPresented: $confirmingReset) {
      Button(Strings.resetToFeed, role: .destructive) {
        selection = nil
        Task { await prices.resetToFeed() }
      }
      .accessibilityIdentifier("settings.sources.priceResetConfirm")
      Button(Strings.cancel, role: .cancel) {}
    }
  }

  private var overridesTable: some View {
    Table(prices.status.overrides, selection: $selection) {
      TableColumn(Strings.priceModel) { row in
        Text(row.model)
          .accessibilityIdentifier("settings.sources.priceRow.\(row.model)")
      }
      TableColumn(Strings.priceInput) { row in rate(row.entry.input) }
      TableColumn(Strings.priceOutput) { row in rate(row.entry.output) }
      TableColumn(Strings.priceCacheRead) { row in rate(row.entry.cacheRead) }
      TableColumn(Strings.priceCacheWrite) { row in rate(row.entry.cacheWrite) }
    }
    .frame(minHeight: 110)
    .accessibilityIdentifier("settings.sources.priceOverrides")
  }

  private func rate(_ value: Int64?) -> some View {
    Text(value.map { "$" + Formatters.perMillion($0, locale: .current) } ?? "\u{2014}")
      .monospacedDigit()
  }

  private func caption(now: Date) -> String {
    let status = prices.status
    let refreshed = Formatters.freshness(status.fetchedAt, now: now, calendar: .current, stale: status.isStale)
    return Strings.priceSnapshotCaption(version: status.version, models: status.models,
                                        overrides: status.overrides.count, refreshed: refreshed)
  }
}

/// `+`: a model and its rates in USD per 1M tokens; `Save` stores the override (`price.override_set`).
struct OverrideSheet: View {
  let prices: PriceBookModel
  @Environment(\.dismiss) private var dismiss
  @State private var model = ""
  @State private var input = ""
  @State private var output = ""
  @State private var cacheRead = ""
  @State private var cacheWrite = ""
  @State private var invalid = false
  @State private var saving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(Strings.priceOverrideSheetTitle)
        .font(.headline)
      Text(Strings.priceOverrideSheetCaption)
        .font(.caption)
        .foregroundStyle(.secondary)
      Form {
        TextField(Strings.priceModel, text: $model)
          .accessibilityIdentifier("settings.price.model")
        TextField(Strings.priceInput, text: $input)
          .accessibilityIdentifier("settings.price.input")
        TextField(Strings.priceOutput, text: $output)
          .accessibilityIdentifier("settings.price.output")
        TextField(Strings.priceCacheRead, text: $cacheRead)
          .accessibilityIdentifier("settings.price.cacheRead")
        TextField(Strings.priceCacheWrite, text: $cacheWrite)
          .accessibilityIdentifier("settings.price.cacheWrite")
      }
      if invalid {
        Text(Strings.priceOverrideInvalid)
          .font(.caption)
          .foregroundStyle(Color(.healthLow))
          .accessibilityIdentifier("settings.price.invalid")
      }
      HStack {
        Spacer()
        Button(Strings.cancel, role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("settings.price.cancel")
        Button(Strings.save) {
          saving = true
          Task {
            let saved = await prices.saveOverride(model: model, input: input, output: output,
                                                  cacheRead: cacheRead, cacheWrite: cacheWrite)
            saving = false
            if saved { dismiss() } else { invalid = true }
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(saving)
        .accessibilityIdentifier("settings.price.save")
      }
    }
    .padding(20)
    .frame(width: 380)
  }
}
