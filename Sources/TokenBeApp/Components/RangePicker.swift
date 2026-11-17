import SwiftUI
import TokenBeCore

/// 08 § Dashboard window toolbar: `Today | 7 d | 30 d | 90 d`, bound to `tb.ui.dashboardRange` (default `7 d`).
struct RangePicker: View {
  @Binding var selection: DashboardRange

  var body: some View {
    Picker(Strings.rangePicker, selection: $selection) {
      ForEach(DashboardRange.allCases, id: \.self) { range in
        Text(Self.label(range)).tag(range)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .accessibilityIdentifier("dashboard.range")
  }

  static func label(_ range: DashboardRange) -> String {
    switch range {
    case .today: Strings.rangeToday
    case .sevenDays: Strings.range7d
    case .thirtyDays: Strings.range30d
    case .ninetyDays: Strings.range90d
    }
  }

  /// The range as VoiceOver reads it: `7 days` for `7 d` (08 § Accessibility).
  static func spokenLabel(_ range: DashboardRange) -> String {
    switch range {
    case .today: Strings.rangeToday
    case .sevenDays: Strings.spokenDays(7)
    case .thirtyDays: Strings.spokenDays(30)
    case .ninetyDays: Strings.spokenDays(90)
    }
  }
}
