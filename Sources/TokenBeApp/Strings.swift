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
  static let quit = "Quit"

  /// VoiceOver label for a band dot (08 § Accessibility: colour is never the only carrier).
  static func bandLabel(_ word: String) -> String { "Band: \(word)" }
}
