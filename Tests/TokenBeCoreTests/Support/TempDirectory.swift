import Foundation
import Synchronization

/// A fresh directory under the system temp folder, removed when the value is deinitialized.
final class TempDirectory: Sendable {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("tokenbe-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      // Best effort: the OS clears its temp folder; failing here must not fail a test.
      _ = error
    }
  }

  func files() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
  }
}

/// A settable wall clock for `now:` parameters.
final class ManualDate: Sendable {
  private let value: Mutex<Date>
  init(_ date: Date) { value = Mutex(date) }
  var date: Date { value.withLock { $0 } }
  func set(_ date: Date) { value.withLock { $0 = date } }
  var provider: @Sendable () -> Date { { [self] in date } }
}
