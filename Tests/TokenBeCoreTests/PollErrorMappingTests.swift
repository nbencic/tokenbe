import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 3.1 step 3: status and transport failures → `PollError` (04 § Error taxonomy).
@Suite struct PollErrorMappingTests {
  static let now = Date(timeIntervalSince1970: 1_794_000_000)

  static func response(_ status: Int, _ headers: [String: String] = [:], body: String = "") -> HTTPResponse {
    HTTPResponse(status: status, headers: headers, body: Data(body.utf8))
  }

  @Test("2xx is not an error", arguments: [200, 201, 204, 299])
  func success(_ status: Int) {
    #expect(PollError.from(Self.response(status)) == nil)
  }

  @Test("401 and 403 → auth with the body", arguments: [401, 403])
  func auth(_ status: Int) {
    #expect(PollError.from(Self.response(status, body: "{\"error\":\"nope\"}"))
            == .auth(http: status, body: "{\"error\":\"nope\"}"))
  }

  @Test("5xx → server", arguments: [500, 502, 503, 599])
  func server(_ status: Int) {
    #expect(PollError.from(Self.response(status, body: "down")) == .server(http: status, body: "down"))
  }

  @Test("other statuses → providerRule, which never retries (Q-026)", arguments: [301, 400, 404, 409, 422])
  func other(_ status: Int) {
    #expect(PollError.from(Self.response(status)) == .providerRule("http \(status)"))
  }

  @Test("429: Retry-After as seconds, HTTP-date, past date, absent, unparseable")
  func rateLimited() throws {
    let cases: [(String?, Duration?)] = [
      ("12", .seconds(12)),
      ("0", .seconds(0)),
      ("  600 ", .seconds(600)),
      (nil, nil),
      ("soon", nil),
      ("-5", nil)
    ]
    for (header, expected) in cases {
      let headers = header.map { ["Retry-After": $0] } ?? [:]
      #expect(PollError.from(Self.response(429, headers), now: Self.now) == .rateLimited(retryAfter: expected),
              "Retry-After \(header ?? "absent")")
    }
    let future = Self.now.addingTimeInterval(90)
    let date = try #require(Self.httpDate(future))
    #expect(PollError.from(Self.response(429, ["retry-after": date]), now: Self.now)
            == .rateLimited(retryAfter: .seconds(90)), "header names are case-insensitive")
    let past = try #require(Self.httpDate(Self.now.addingTimeInterval(-30)))
    #expect(PollError.from(Self.response(429, ["Retry-After": past]), now: Self.now)
            == .rateLimited(retryAfter: .zero))
    #expect(PollError.from(Self.response(429, ["Retry-After": "3600"]), now: Self.now)
            == .rateLimited(retryAfter: .seconds(3600)), "the parser does not cap; RetryPolicy does")
  }

  @Test("transport failures")
  func transport() {
    #expect(PollError.from(TransportError.urlError(URLError(.timedOut))) == .transport(URLError(.timedOut)))
    #expect(PollError.from(TransportError.urlError(URLError(.cancelled))) == .cancelled)
    #expect(PollError.from(TransportError.tooLarge(limit: 10)) == .decode(field: "body", path: "larger than 10 bytes"))
    #expect(PollError.from(TransportError.notHTTP) == .transport(URLError(.badServerResponse)))
    #expect(PollError.from(TransportError.noFixture("GET x")) == .providerRule("no fixture for GET x"))
  }

  static func httpDate(_ date: Date) -> String? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return formatter.string(from: date)
  }
}
