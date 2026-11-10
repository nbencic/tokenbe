import Foundation
import Synchronization

/// Response bodies on their way to diagnostics (02 RULE, 03 `poll_state.last_raw`, R8): redacted first, then cut to
/// 64 KiB on a character boundary. Redaction runs before truncation so a cut key cannot slip past the patterns (07).
public enum RawBody {
  public static let limit = 64 * 1024

  public static func redacted(_ data: Data, redactor: Redactor) -> String {
    let text = String(bytes: data, encoding: .utf8) ?? "<\(data.count) bytes, not UTF-8>"
    return truncated(redactor.redact(text))
  }

  /// The longest prefix of `text` whose UTF-8 encoding fits in `limit` bytes.
  public static func truncated(_ text: String, limit: Int = RawBody.limit) -> String {
    guard text.utf8.count > limit else { return text }
    var end = text.startIndex
    var bytes = 0
    for index in text.indices {
      let size = text[index].utf8.count
      guard bytes + size <= limit else { break }
      bytes += size
      end = text.index(after: index)
    }
    return String(text[..<end])
  }
}

/// The last response body an adapter received during one job (14 § Stage 3.4 step 5), kept unredacted only for the
/// length of that job. The poller stores it, redacted, as `poll_state.last_raw`, and samples it for
/// `poll.schema_drift` when decoding fails (04 § Retry policy: "decode … last_raw holds the body").
public final class ResponseTrace: Sendable {
  private let body = Mutex<Data?>(nil)

  public init() {}

  public func record(_ data: Data) {
    body.withLock { $0 = data }
  }

  public var lastBody: Data? { body.withLock { $0 } }
}
