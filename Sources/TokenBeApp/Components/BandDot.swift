import SwiftUI
import TokenBeCore

extension Band {
  /// The band's health colour (08 § Design tokens); never the only carrier of the band (08 § Accessibility).
  var color: Color {
    switch self {
    case .healthy: Color(.healthHealthy)
    case .watch: Color(.healthWatch)
    case .low: Color(.healthLow)
    case .critical: Color(.healthCritical)
    case .unknown: Color(.healthUnknown)
    }
  }
}

/// The 8 pt band dot of cards and sidebar rows (08), labelled with the band word for VoiceOver.
struct BandDot: View {
  let band: Band

  var body: some View {
    Circle()
      .fill(band.color)
      .frame(width: 8, height: 8)
      .accessibilityLabel(Strings.bandLabel(band.word))
  }
}
