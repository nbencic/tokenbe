import Foundation
import Testing
@testable import TokenBeCore

/// 07 § Redaction: 7 patterns, real-shaped fake keys, exact pass; output never shows more than the last 4 characters.
@Suite struct RedactorTests {
  /// Random alphanumerics, so a leaked fragment cannot be confused with surrounding text.
  static func body(_ count: Int, alphabet: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    -> String {
    String((0..<count).map { _ in alphabet.randomElement() ?? "x" })
  }

  /// Fails if any 5-character window of `secret` survives in `output` (07: never more than the last 4 chars).
  static func expectNoLeak(of secret: String, in output: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let characters = Array(secret)
    guard characters.count >= 5 else { return }
    for start in 0...(characters.count - 5) {
      let window = String(characters[start..<(start + 5)])
      #expect(!output.contains(window), "leaked \(window) in \(output)", sourceLocation: sourceLocation)
    }
  }

  @Test("pattern 1: sk- keys (OpenAI project/admin, DeepSeek)")
  func pattern1() {
    let redactor = Redactor()
    for secret in ["sk-proj-" + Self.body(48), "sk-admin-" + Self.body(40), "sk-" + Self.body(32, alphabet: "0123456789abcdef")] {
      let out = redactor.redact("calling with \(secret) now")
      #expect(out == "calling with «redacted:key» now")
      Self.expectNoLeak(of: String(secret.dropFirst(3)), in: out)
    }
  }

  @Test("pattern 2: sk-ant- keys")
  func pattern2() {
    // Split so the source never contains a key-shaped literal (check-no-secrets.sh scans the tree).
    let secret = "sk-" + "ant-admin01-" + Self.body(80) + "-" + Self.body(6)
    let out = Redactor().redact("key=\(secret)")
    #expect(!out.contains("sk-ant-"))
    Self.expectNoLeak(of: String(secret.dropFirst(7)), in: out)
  }

  @Test("pattern 3: auth headers, with scheme word and JSON quoting")
  func pattern3() {
    let redactor = Redactor()
    let token = Self.body(40)
    let cases = [
      "Authorization: Bearer \(token)",
      "authorization=Basic \(token)",
      "x-api-key: \(token)",
      "X-Goog-Api-Key:\(token)",
      "{\"x-api-key\": \"\(token)\", \"other\": 1}",
      "{\"Authorization\":\"Bearer \(token)\"}"
    ]
    for input in cases {
      let out = redactor.redact(input)
      #expect(out.contains("«redacted:header»"), "\(out)")
      Self.expectNoLeak(of: token, in: out)
    }
    #expect(redactor.redact("x-api-key: \(token) next") == "x-api-key: «redacted:header» next")
    #expect(redactor.redact("{\"x-api-key\": \"\(token)\"}") == "{\"x-api-key\": \"«redacted:header»\"}")
  }

  @Test("pattern 3 regression: the token after the scheme word is not left behind (Q-006)")
  func pattern3SchemeRegression() {
    let jwt = "eyJ" + Self.body(30) + "." + Self.body(40) + "." + Self.body(20)
    let out = Redactor().redact("Authorization: Bearer \(jwt)")
    #expect(out == "Authorization: «redacted:header»")
  }

  @Test("pattern 4: bearer tokens, including + / =")
  func pattern4() {
    let token = Self.body(20) + "+/" + Self.body(20) + "=="
    let out = Redactor().redact("sent bearer \(token) upstream")
    #expect(out == "sent Bearer «redacted:token» upstream")
    Self.expectNoLeak(of: token, in: out)
  }

  @Test("pattern 5: xai- keys")
  func pattern5() {
    let secret = "xai-" + Self.body(80)
    let out = Redactor().redact("[\(secret)]")
    #expect(out == "[«redacted:key»]")
  }

  @Test("pattern 6: sk-or-v1- keys")
  func pattern6() {
    let secret = "sk-or-v1-" + Self.body(64, alphabet: "0123456789abcdef")
    let out = Redactor().redact(secret)
    #expect(out == "«redacted:key»")
  }

  @Test("pattern 7: registered secrets of unknown format, as substrings, until unregistered")
  func pattern7() {
    let redactor = Redactor()
    let secret = "zz9_" + Self.body(30)
    redactor.register(secret: secret)
    let out = redactor.redact("https://host/path?token=\(secret)&x=1")
    #expect(out == "https://host/path?token=«redacted:key»&x=1")
    redactor.register(secret: secret)
    redactor.unregister(secret: secret)
    #expect(redactor.redact(secret) == "«redacted:key»", "still held by the second registration")
    redactor.unregister(secret: secret)
    #expect(redactor.redact(secret) == secret)
    redactor.unregister(secret: "never-registered")
    redactor.register(secret: "")
    #expect(redactor.redact("plain") == "plain")
  }

  @Test("pattern 7: a longer secret containing a shorter one is removed whole")
  func pattern7LongestFirst() {
    let redactor = Redactor()
    let short = "custom" + Self.body(10)
    let long = short + Self.body(10)
    redactor.register(secret: short)
    redactor.register(secret: long)
    #expect(redactor.redact("v=\(long)") == "v=«redacted:key»")
  }

  @Test("records: msg, ctx, err and acct are redacted before any sink sees them")
  func recordFieldsRedacted() async {
    let secret = "sk-proj-" + Self.body(48)
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    struct Failure: Error, LocalizedError {
      let text: String
      var errorDescription: String? { text }
    }
    pipeline.emit(
      .error, .pollFailed, cat: .poll("openai"), msg: "failed with \(secret)", acct: "acct \(secret)",
      err: Failure(text: "server echoed \(secret)"), ctx: ["header": .string("Authorization: Bearer \(secret)")]
    )
    await pipeline.drain()
    let line = await sink.lines().joined()
    #expect(line.contains("«redacted:"))
    Self.expectNoLeak(of: String(secret.dropFirst(3)), in: line)
  }

  @Test("redaction runs before truncation: a key straddling the 512 limit is not partly kept")
  func redactBeforeTruncate() {
    let secret = "sk-" + Self.body(40)
    let message = String(repeating: "a", count: 505) + secret
    let record = LogRecord.sanitized(
      ts: Date(), lvl: .info, cat: .app, evt: .appLaunch, msg: message, acct: nil, job: nil, attempt: nil,
      err: nil, durMs: nil, ctx: [:], pid: 1, thr: "main", v: "test", redactor: Redactor()
    )
    Self.expectNoLeak(of: String(secret.dropFirst(3)), in: record.msg)
    #expect(record.msg.count == 512)
  }
}
