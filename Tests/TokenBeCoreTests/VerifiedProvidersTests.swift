import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 3.3 step 5 / 11: `Verified.providers` ↔ `Tests/Fixtures/providers/<p>/RECORDED`, both directions. A
/// marker's first line is its recording date, `YYYY-MM-DD` (written by `scripts/record-fixtures.sh`).
@Suite struct VerifiedProvidersTests {
  /// `Tests/Fixtures/providers`, read from this file's location (PM-2.1-1).
  static func providersDirectory() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/providers", isDirectory: true)
  }

  /// Providers with a `RECORDED` marker; a missing `providers/` folder means none.
  static func markers(in directory: URL) -> Set<ProviderID> {
    Set(ProviderID.allCases.filter {
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("\($0.rawValue)/RECORDED").path)
    })
  }

  static func recordedDate(_ marker: URL) -> Date? {
    guard let data = FileManager.default.contents(atPath: marker.path),
          let first = String(bytes: data, encoding: .utf8)?.split(separator: "\n").first else { return nil }
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(identifier: "UTC")
    parser.dateFormat = "yyyy-MM-dd"
    return parser.date(from: String(first).trimmingCharacters(in: .whitespaces))
  }

  @Test("every verified provider has a dated RECORDED marker")
  func verifiedHaveMarkers() {
    let directory = Self.providersDirectory()
    for provider in Verified.providers {
      let marker = directory.appendingPathComponent("\(provider.rawValue)/RECORDED")
      #expect(Self.recordedDate(marker) != nil, "\(provider) is verified but \(marker.path) is missing or undated")
    }
  }

  @Test("every RECORDED marker belongs to a verified provider")
  func markersAreVerified() {
    let unverified = Self.markers(in: Self.providersDirectory()).subtracting(Verified.providers)
    #expect(unverified.isEmpty, "RECORDED without a Verified.swift entry: \(unverified.map(\.rawValue).sorted())")
  }

  @Test("marker parsing: a dated marker counts, an undated one does not, a missing folder means none")
  func parsing() throws {
    let temp = try TempDirectory()
    #expect(Self.markers(in: temp.url.appendingPathComponent("absent")).isEmpty)
    let folder = temp.url.appendingPathComponent("xai", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let marker = folder.appendingPathComponent("RECORDED")
    try Data("2026-11-10\nrecorded by record-fixtures.sh\n".utf8).write(to: marker)
    #expect(Self.markers(in: temp.url) == [.xai])
    #expect(Self.recordedDate(marker) != nil)
    try Data("soon\n".utf8).write(to: marker)
    #expect(Self.recordedDate(marker) == nil)
  }
}
