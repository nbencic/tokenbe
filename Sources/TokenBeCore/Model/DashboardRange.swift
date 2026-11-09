/// The Dashboard's range picker (08 § Dashboard window; `tb.ui.dashboardRange`, 09). Raw values are the setting's.
public enum DashboardRange: String, CaseIterable, Sendable {
  case today
  case sevenDays = "7d"
  case thirtyDays = "30d"
  case ninetyDays = "90d"

  /// 09's default.
  public static let `default`: DashboardRange = .sevenDays

  /// The stored setting, or the default for anything else (09 validation already clamps to the allowed values).
  public init(setting: String) {
    self = DashboardRange(rawValue: setting) ?? .default
  }
}
