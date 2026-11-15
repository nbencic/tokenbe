import SwiftUI
import TokenBeCore

/// Settings → Alerts (08 § Settings, Paper `18L-0`; 09 § Alerts; 14 § Stage 5.3 step 6): the band thresholds in days
/// (`Settings` repairs `critical < low < watch` with a log), the dollar floor, the stale multiplier, the drift
/// threshold (read in 8.1) and the anchor-age nudge. The notification toggles and quiet hours join in 5.4.
struct AlertsTab: View {
  @Bindable var settings: TokenBeCore.Settings

  var body: some View {
    Form {
      Section(Strings.thresholds) {
        stepper(Strings.watchDays, $settings.alertsWatchDays, .alertsWatchDays, Strings.days, "watchDays")
        stepper(Strings.lowDays, $settings.alertsLowDays, .alertsLowDays, Strings.days, "lowDays")
        stepper(Strings.criticalDays, $settings.alertsCriticalDays, .alertsCriticalDays, Strings.days, "criticalDays")
        Stepper(value: $settings.alertsDollarFloorCents, in: bounds(.alertsDollarFloorCents), step: 100) {
          LabeledContent(Strings.dollarFloor, value: Formatters.money(
            Money(cents: Int64(settings.alertsDollarFloorCents)), hideCents: true, locale: .current
          ))
        }
        .accessibilityIdentifier("settings.alerts.dollarFloor")
      }
      Section {
        stepper(Strings.staleMultiplier, $settings.alertsStaleMultiplier, .alertsStaleMultiplier, Strings.intervals,
                "staleMultiplier")
        stepper(Strings.driftThreshold, $settings.alertsDriftThresholdPct, .alertsDriftThresholdPct, Strings.percent,
                "driftThreshold")
        stepper(Strings.anchorAge, $settings.alertsAnchorAgeDays, .alertsAnchorAgeDays, Strings.days, "anchorAge")
      }
    }
    .formStyle(.grouped)
  }

  private func bounds(_ key: SettingsKey) -> ClosedRange<Int> { key.spec.intBounds ?? 0...365 }

  private func stepper(_ label: String, _ value: Binding<Int>, _ key: SettingsKey, _ text: (Int) -> String,
                       _ id: String) -> some View {
    Stepper(value: value, in: bounds(key)) {
      LabeledContent(label, value: text(value.wrappedValue))
    }
    .accessibilityIdentifier("settings.alerts.\(id)")
  }
}
