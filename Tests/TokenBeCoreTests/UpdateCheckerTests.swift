import Foundation
import Testing
@testable import TokenBeCore

/// 11 `UpdateCheckerTests` (14 § Stage 9.4; 02 § Update check): semver compare, the `v` prefix, the ignored version;
/// `update.check_ok` / `update.check_failed`; one GET a day; the release page (Q-058). Over `StubTransport`.
@Suite struct UpdateCheckerTests {
  static let path = "/repos/nbencic/tokenbe/releases/latest"

  static func release(_ tag: String, page: String = "https://github.com/nbencic/tokenbe/releases/tag/v1.2.0",
                      status: Int = 200) -> StubTransport.Answer {
    let body = #"{"tag_name":"\#(tag)","html_url":"\#(page)","assets":[],"body":"notes"}"#
    return .response(HTTPResponse(status: status, headers: [:], body: Data(body.utf8)))
  }

  struct Harness {
    let transport = StubTransport()
    let sink = CapturingLogSink()
    let pipeline: LogPipeline

    init() {
      pipeline = LogPipeline(sinks: [sink], version: "test")
      pipeline.startConsumer()
    }

    func check(_ answer: StubTransport.Answer, current: String = "1.1.0") async -> UpdateChecker.Outcome {
      await transport.on("GET", UpdateCheckerTests.path, answer)
      return await UpdateChecker(transport: transport, logPipeline: pipeline).check(current: current)
    }

    func records(_ evt: Evt) async -> [LogRecord] {
      await pipeline.drain()
      return await sink.records.filter { $0.evt == evt }
    }
  }

  @Test("semver: numeric parts, the v prefix, a prerelease below its release, build metadata ignored")
  func semver() throws {
    #expect(SemVer("v1.2.3") == SemVer("1.2.3") && SemVer("V1.2.3")?.description == "1.2.3")
    #expect(try #require(SemVer("1.10.0")) > #require(SemVer("1.9.9")), "numeric, not text")
    #expect(try #require(SemVer("1.0.0-beta.2")) < #require(SemVer("1.0.0")))
    #expect(try #require(SemVer("1.0.0-beta.2")) < #require(SemVer("1.0.0-beta.10")))
    #expect(try #require(SemVer("1.0.0-alpha")) < #require(SemVer("1.0.0-alpha.1")))
    #expect(try #require(SemVer("1.0.0-1")) < #require(SemVer("1.0.0-alpha")), "numeric identifiers sort first")
    #expect(try #require(SemVer("1.0.0-beta")) > #require(SemVer("1.0.0-alpha")))
    #expect(SemVer("1.0.0+build.7") == SemVer("1.0.0") && SemVer("1.0.0-rc.1+x")?.description == "1.0.0-rc.1")
    for bad in ["", "1.0", "1.0.0.0", "dev", "1.x.0", "v", "1.0.0-", "-1.0.0", "１.0.0"] {
      #expect(SemVer(bad) == nil, "\(bad) is not a version")
    }
  }

  @Test("the badge: newer than the bundle and not the skipped version; unparsable shows nothing")
  func available() {
    #expect(UpdateChecker.isUpdateAvailable(latestSeen: "1.2.0", current: "1.1.0", ignored: ""))
    #expect(!UpdateChecker.isUpdateAvailable(latestSeen: "1.2.0", current: "1.2.0", ignored: ""))
    #expect(!UpdateChecker.isUpdateAvailable(latestSeen: "1.1.0", current: "1.2.0", ignored: ""))
    #expect(!UpdateChecker.isUpdateAvailable(latestSeen: "1.2.0", current: "1.1.0", ignored: "1.2.0"), "skipped")
    #expect(UpdateChecker.isUpdateAvailable(latestSeen: "1.3.0", current: "1.1.0", ignored: "1.2.0"),
            "a newer release than the skipped one shows again")
    #expect(!UpdateChecker.isUpdateAvailable(latestSeen: "", current: "1.1.0", ignored: ""))
    #expect(!UpdateChecker.isUpdateAvailable(latestSeen: "1.2.0", current: "dev", ignored: ""))
  }

  @Test("a newer release: update.check_ok {latest, current, newer: true}; v stripped; the release page kept")
  func newer() async throws {
    let harness = Harness()
    let outcome = await harness.check(Self.release("v1.2.0"))
    #expect(outcome == .checked(latest: "1.2.0", page: URL(string: "https://github.com/nbencic/tokenbe/releases/tag/v1.2.0"),
                                newer: true))
    let calls = await harness.transport.calls
    #expect(calls.count == 1 && calls.first?.url.host() == "api.github.com" && calls.first?.method == "GET")
    #expect(calls.first?.headers["Accept"] == "application/vnd.github+json" && calls.first?.body == nil)
    let records = await harness.records(.updateCheckOk)
    #expect(records.count == 1 && records.first?.lvl == .info && records.first?.cat == .update)
    #expect(records.first?.ctx == ["latest": "1.2.0", "current": "1.1.0", "newer": true])
  }

  @Test("the same or an older release: newer false; an html_url off TokenBe's releases is not kept")
  func notNewer() async {
    let harness = Harness()
    #expect(await harness.check(Self.release("1.1.0", page: "https://example.com/x")) == .checked(latest: "1.1.0",
                                                                                                page: nil, newer: false))
    #expect(await harness.records(.updateCheckOk).first?.ctx["newer"] == false)
    #expect(UpdateChecker.page("https://github.com/nbencic/tokenbe-evil/releases/tag/v1") == nil)
    #expect(UpdateChecker.page(version: "1.2.0")?.absoluteString == "https://github.com/nbencic/tokenbe/releases/tag/v1.2.0")
  }

  @Test("failures log update.check_failed (warn) and change nothing: transport, 404, a body or tag that is not a release")
  func failures() async {
    let cases: [StubTransport.Answer] = [
      .failure(.urlError(URLError(.notConnectedToInternet))), Self.release("v1.2.0", status: 404),
      .response(HTTPResponse(status: 200, headers: [:], body: Data("[]".utf8))), Self.release("latest")
    ]
    for answer in cases {
      let harness = Harness()
      #expect(await harness.check(answer) == .failed)
      let failed = await harness.records(.updateCheckFailed)
      #expect(failed.count == 1 && failed.first?.lvl == .warn && failed.first?.err != nil)
      #expect(await harness.records(.updateCheckOk).isEmpty)
    }
  }

  @Test("one GET a day: due when never checked or on a new UTC day, not again the same day")
  func due() {
    let now = Date(timeIntervalSince1970: 1_795_003_200)
    #expect(UpdateChecker.isDue(lastCheckedAt: 0, now: now))
    #expect(!UpdateChecker.isDue(lastCheckedAt: now.timeIntervalSince1970 - 3_600, now: now))
    #expect(UpdateChecker.isDue(lastCheckedAt: now.timeIntervalSince1970 - 86_400, now: now))
  }
}
