/// Every user-visible string (12 § R9, 08), exactly as 08 writes it. Views never contain inline copy.
enum Strings {
  static let appName = "TokenBe"

  // Popover — Empty state (08 § Popover states)
  static let emptyHeadline = "No accounts yet"
  static let emptyBody = "Add a provider key to start tracking."

  // Popover — cards (08 § Popover, § Popover states)
  static let noDataYet = "No data yet"
  static let modeAnchored = "\u{2248}"
  static let modeSpendOnly = "spend"

  // Popover — footer (08 § Popover 4)
  static let openDashboard = "Open dashboard"
  static let quit = "Quit"

  // Dashboard window (08 § Dashboard window, 14 § Stage 1.2)
  static let dashboardTitle = "Dashboard"
  static let overview = "Overview"
  static let spendByDay = "Spend by day"
  static let noSpendInRange = "No spend in this range"
  static let rangePicker = "Range"
  static let rangeToday = "Today"
  static let range7d = "7 d"
  static let range30d = "30 d"
  static let range90d = "90 d"

  /// VoiceOver label for a band dot (08 § Accessibility: colour is never the only carrier).
  static func bandLabel(_ word: String) -> String { "Band: \(word)" }
}
