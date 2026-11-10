import Foundation

/// RFC 9562 UUID version 7: 48-bit Unix milliseconds, then random bits. 03: "All ids are UUIDv7 strings unless the
/// provider supplies one". Lowercase, so ids sort by creation time as text.
public enum UUIDv7 {
  public static func make(at date: Date = Date(), using rng: inout some RandomNumberGenerator) -> String {
    let millis = UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
    var bytes = [UInt8](repeating: 0, count: 16)
    for index in 0..<6 { bytes[index] = UInt8(truncatingIfNeeded: millis >> (8 * (5 - index))) }
    for index in 6..<16 { bytes[index] = UInt8.random(in: 0...255, using: &rng) }
    bytes[6] = (bytes[6] & 0x0F) | 0x70   // version 7
    bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 9562 variant
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4),
                 hex.dropFirst(20)]
    return parts.joined(separator: "-")
  }

  public static func make(at date: Date = Date()) -> String {
    var rng = SystemRandomNumberGenerator()
    return make(at: date, using: &rng)
  }
}
