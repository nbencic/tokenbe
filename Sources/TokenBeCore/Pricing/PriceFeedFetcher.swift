import CryptoKit
import Foundation

/// The daily LiteLLM fetch (02 § Price feed, 14 § Stage 5.1 step 3): `GET` with `If-None-Match`, a 10 s timeout,
/// a 20 MB body limit and a sha256 compared with the current snapshot. A failure never replaces the current
/// snapshot: it logs `price.feed_failed {reason}` (transport, size, shape; O-6) or `price.parse_failed` and the
/// caller keeps what it has.
public struct PriceFeedFetcher: Sendable {
  /// 02: body limit 20 MB.
  public static let maxBytes = 20 * 1024 * 1024
  /// 02: 10 s timeout.
  public static let timeout: TimeInterval = 10

  /// What one fetch found.
  public enum Outcome: Sendable, Equatable {
    /// HTTP 304: the feed has not changed since `etag`.
    case notModified(etag: String?)
    /// A 200 whose body hashes to the current snapshot's sha256.
    case unchanged(etag: String?)
    /// A new, parsed document.
    case new(body: Data, etag: String?, sha256: String, table: PriceTable)
    /// Logged here; the current snapshot stays.
    case failed(reason: String)
  }

  let transport: any HTTPTransport
  let log: EventLog

  public init(transport: any HTTPTransport, logPipeline: LogPipeline? = nil) {
    self.transport = transport
    log = EventLog(pipeline: logPipeline)
  }

  /// `current` is the snapshot in use (its ETag is sent, its sha256 compared, its version named on failure).
  public func fetch(url: URL, current: PriceSnapshotRecord?) async -> Outcome {
    var headers: [String: String] = [:]
    if let etag = current?.etag { headers["If-None-Match"] = etag }
    let response: HTTPResponse
    do {
      response = try await transport.send(HTTPRequest(url: url, headers: headers, timeout: Self.timeout))
    } catch {
      if case .tooLarge = error { return failed("size", error, current) }
      return failed("transport", error, current)
    }
    let etag = response.header("ETag")
    if response.status == 304 { return .notModified(etag: etag ?? current?.etag) }
    guard (200..<300).contains(response.status) else {
      return failed("transport", HTTPStatus(status: response.status), current)
    }
    guard response.body.count <= Self.maxBytes else {
      return failed("size", TransportError.tooLarge(limit: Self.maxBytes), current)
    }
    let sha = Self.sha256(response.body)
    if sha == current?.sha256 { return .unchanged(etag: etag) }
    let table: PriceTable
    do {
      table = try PriceTable.parse(response.body)
    } catch {
      log.emit(.warn, .priceParseFailed, cat: .price, msg: "price feed is not a JSON object", err: error,
               ctx: ["bytes": .int(response.body.count)])
      return .failed(reason: "parse")
    }
    if table.shapeChanged {
      return failed("shape", ShapeChanged(entries: table.entries.count, withInputRate: table.withInputRate), current)
    }
    return .new(body: response.body, etag: etag, sha256: sha, table: table)
  }

  private func failed(_ reason: String, _ error: any Error, _ current: PriceSnapshotRecord?) -> Outcome {
    log.emit(.warn, .priceFeedFailed, cat: .price, msg: "price feed not refreshed", err: error, ctx: [
      "reason": .string(reason), "using_cached_from": current.map { .string($0.version) } ?? .null
    ])
    return .failed(reason: reason)
  }

  /// Lowercase hex, as `shasum -a 256` prints it (the bundled `.sha256` file).
  public static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// A non-2xx, non-304 answer.
  struct HTTPStatus: Error, CustomStringConvertible {
    let status: Int
    var description: String { "HTTP \(status)" }
  }

  /// O-6: most chat entries lost `input_cost_per_token`.
  struct ShapeChanged: Error, CustomStringConvertible {
    let entries: Int
    let withInputRate: Int
    var description: String { "\(withInputRate) of \(entries) chat entries have input_cost_per_token" }
  }
}
