/// Health band of an account (05 § Bands, D-bands). Stale is an overlay, not a band.
public enum Band: String, CaseIterable, Sendable, Comparable {
  case healthy, watch, low, critical, unknown

  /// Severity order used for "worst band" decisions: unknown is not worse than critical.
  private var severity: Int {
    switch self {
    case .healthy: 0
    case .watch: 1
    case .unknown: 2
    case .low: 3
    case .critical: 4
    }
  }

  public static func < (lhs: Band, rhs: Band) -> Bool { lhs.severity < rhs.severity }

  /// The word read by VoiceOver and shown next to colour (08 § Accessibility: colour is never the only carrier).
  public var word: String { rawValue }
}
