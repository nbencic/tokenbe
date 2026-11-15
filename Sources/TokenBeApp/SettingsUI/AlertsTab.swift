import SwiftUI
import TokenBeCore

/// Settings → Alerts (08 § Settings, Paper `18L-0`; 09 § Alerts; 14 § Stage 5.3 step 6): the band thresholds in days
/// (`Settings` repairs `critical < low < watch` with a log), the dollar floor, the stale multiplier, the drift
/// threshold (read in 8.1) and the anchor-age nudge; 5.4's notification toggles per band, quiet hours,
/// `Send test notification`, and the `Notifications are off in System Settings` banner when denied (O-11).
struct AlertsTab: View {
  @Bindable var settings: TokenBeCore.Settings
  let model: AppModel
  @State private var testResult: Bool?

  var body: some View {
    Form {
      if model.notificationsAllowed == false {
        Section {
          HStack {
            Text(Strings.notificationsOff)
              .foregroundStyle(Color(.healthWatch))
              .accessibilityIdentifier("settings.alerts.denied")
            Spacer()
            Button(Strings.openSystemSettings) {
              if let url = URL(string: Strings.notificationSettingsURL) { NSWorkspace.shared.open(url) }
            }
            .accessibilityIdentifier("settings.alerts.openSystemSettings")
          }
        }
      }
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
      Section(Strings.notifications) {
        Toggle(Strings.notifyLow, isOn: $settings.alertsNotifyLow)
          .accessibilityIdentifier("settings.alerts.notifyLow")
        Toggle(Strings.notifyCritical, isOn: $settings.alertsNotifyCritical)
          .accessibilityIdentifier("settings.alerts.notifyCritical")
        Toggle(Strings.notifyUnknown, isOn: $settings.alertsNotifyUnknown)
          .accessibilityIdentifier("settings.alerts.notifyUnknown")
        Toggle(Strings.notifyStale, isOn: $settings.alertsNotifyStale)
          .accessibilityIdentifier("settings.alerts.notifyStale")
        Toggle(Strings.quietHours, isOn: $settings.alertsQuietHoursEnabled)
          .accessibilityIdentifier("settings.alerts.quietHours")
        DatePicker(Strings.quietFrom, selection: time($settings.alertsQuietStart), displayedComponents: .hourAndMinute)
          .disabled(!settings.alertsQuietHoursEnabled)
          .accessibilityIdentifier("settings.alerts.quietStart")
        DatePicker(Strings.quietUntil, selection: time($settings.alertsQuietEnd), displayedComponents: .hourAndMinute)
          .disabled(!settings.alertsQuietHoursEnabled)
          .accessibilityIdentifier("settings.alerts.quietEnd")
        HStack {
          Button(Strings.sendTestNotification) {
            Task { testResult = await model.sendTestNotification() }
          }
          .accessibilityIdentifier("settings.alerts.sendTest")
          if let testResult {
            Text(testResult ? Strings.testSent : Strings.testNotSent)
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("settings.alerts.testResult")
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  /// `HH:mm` (09) as a time of day for the picker; the picker's choice is written back as `HH:mm`.
  private func time(_ text: Binding<String>) -> Binding<Date> {
    Binding(
      get: {
        let minutes = AlertSettings.minutes(text.wrappedValue) ?? 0
        return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
      },
      set: { date in
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        text.wrappedValue = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
      }
    )
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
