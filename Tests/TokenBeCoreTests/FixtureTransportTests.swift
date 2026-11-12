import Foundation
import Network
import Testing
@testable import TokenBeCore

/// 14 § Stage 3.1 step 5: the fixture envelope (Q-026), `FixtureTransport` routing and file choice, `StubTransport`,
/// and the transport factory for `tb.debug.fixtureMode` (09). Fixture files are written to a temp folder: none is
/// committed before `record-fixtures.sh --verify-redacted` exists (R11).
@Suite struct FixtureTransportTests {
  static let route = FixtureTransport.Route(hostPath: "api.openai.com/v1/organization/costs", provider: .openai,
                                            endpoint: "costs")

  static func write(_ text: String, _ name: String, in root: URL, provider: String = "openai") throws {
    let folder = root.appendingPathComponent(provider, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(text.utf8).write(to: folder.appendingPathComponent(name))
  }

  static func request(_ path: String = "/v1/organization/costs?start_time=1", method: String = "GET") throws -> HTTPRequest {
    HTTPRequest(method: method, url: try #require(URL(string: "https://api.openai.com\(path)")))
  }

  @Test("the envelope gives status, headers and the body as JSON")
  func envelope() throws {
    let response = try FixtureEnvelope.decode(
      Data(#"{"status":429,"headers":{"Retry-After":"12"},"body":{"error":{"code":"rate_limit"}}}"#.utf8), name: "t")
    #expect(response.status == 429)
    #expect(response.header("retry-after") == "12")
    #expect(utf8Text(response.body) == #"{"error":{"code":"rate_limit"}}"#)
    let noHeaders = try FixtureEnvelope.decode(Data(#"{"status":200,"body":[1,2]}"#.utf8), name: "t")
    #expect(noHeaders.headers.isEmpty)
    #expect(utf8Text(noHeaders.body) == "[1,2]")
  }

  @Test("a malformed envelope is a shape error", arguments: [
    "not json", #"{"body":{}}"#, #"{"status":"200","body":{}}"#, #"{"status":200}"#,
    #"{"status":200,"headers":{"a":1},"body":{}}"#, "[1]"
  ])
  func malformed(_ text: String) {
    #expect(throws: FixtureEnvelope.LoadError.self) { try FixtureEnvelope.decode(Data(text.utf8), name: "t") }
  }

  @Test("routes by method and host+path, ignores the query, prefers recorded over synthetic")
  func routing() async throws {
    let temp = try TempDirectory()
    try Self.write(#"{"status":200,"body":{"source":"synthetic"}}"#, "costs.ok.synthetic.json", in: temp.url)
    let transport = FixtureTransport(root: temp.url, routes: [Self.route])
    let synthetic = try await transport.send(try Self.request())
    #expect(utf8Text(synthetic.body) == #"{"source":"synthetic"}"#)

    try Self.write(#"{"status":200,"body":{"source":"recorded"}}"#, "costs.ok.recorded.json", in: temp.url)
    let recorded = try await transport.send(try Self.request())
    #expect(utf8Text(recorded.body) == #"{"source":"recorded"}"#)

    await #expect(throws: TransportError.noFixture("POST api.openai.com/v1/organization/costs")) {
      try await transport.send(try Self.request(method: "POST"))
    }
    await #expect(throws: TransportError.noFixture("GET api.openai.com/v1/other")) {
      try await transport.send(try Self.request("/v1/other"))
    }
  }

  @Test("a case other than ok is chosen per endpoint; a missing or bad file is noFixture")
  func cases() async throws {
    let temp = try TempDirectory()
    try Self.write(#"{"status":401,"body":{"error":"bad key"}}"#, "costs.auth.401.synthetic.json", in: temp.url)
    let failing = FixtureTransport(root: temp.url, routes: [Self.route], cases: ["openai/costs": "auth.401"])
    #expect(try await failing.send(try Self.request()).status == 401)

    let missing = FixtureTransport(root: temp.url, routes: [Self.route])
    await #expect(throws: TransportError.noFixture(
      "openai/costs: no costs.ok.recorded.json or costs.ok.synthetic.json")) {
      try await missing.send(try Self.request())
    }

    try Self.write("{", "costs.broken.synthetic.json", in: temp.url)
    let broken = FixtureTransport(root: temp.url, routes: [Self.route], cases: ["openai/costs": "broken"])
    do {
      _ = try await broken.send(try Self.request())
      Issue.record("expected noFixture")
    } catch {
      guard let transportError = error as? TransportError, case .noFixture(let detail) = transportError else {
        Issue.record("unexpected \(error)")
        return
      }
      #expect(detail.hasPrefix("openai/costs: "))
    }
  }

  @Test("the default root is the source tree's Tests/Fixtures/providers")
  func sourceTreeRoot() {
    let root = FixtureTransport.sourceTreeRoot()
    #expect(root.path().hasSuffix("/Tests/Fixtures/providers/"))
    #expect(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("README.md").path))
  }

  @Test("tb.debug.fixtureMode picks FixtureTransport in DEBUG, the network otherwise")
  func factory() {
    #expect(Transports.make(fixtureMode: true, version: "1") is FixtureTransport)
    #expect(Transports.make(fixtureMode: false, version: "1") is URLSessionTransport)
  }

  @Test("StubTransport answers in turn, serves fixture files, and records the call order")
  func stub() async throws {
    let temp = try TempDirectory()
    try Self.write(#"{"status":500,"body":"oops"}"#, "server.500.synthetic.json", in: temp.url)
    let stub = StubTransport()
    await stub.on("GET", "/a", .response(HTTPResponse(status: 200)), .failure(.urlError(URLError(.timedOut))))
    await stub.on("GET", "/b", .fixture(temp.url.appendingPathComponent("openai/server.500.synthetic.json")))
    let first = try Self.request("/a")
    #expect(try await stub.send(first).status == 200)
    await #expect(throws: TransportError.urlError(URLError(.timedOut))) { try await stub.send(first) }
    await #expect(throws: TransportError.urlError(URLError(.timedOut))) { try await stub.send(first) }
    #expect(try await stub.send(try Self.request("/b")).status == 500)
    await #expect(throws: TransportError.noFixture("GET /c")) { try await stub.send(try Self.request("/c")) }
    #expect(await stub.callOrder == ["GET /a", "GET /a", "GET /a", "GET /b", "GET /c"])
  }

  @Test("the OpenAI routes serve the committed synthetic fixtures; page=<cursor> selects that page's file")
  func openAIRoutes() async throws {
    let transport = FixtureTransport(routes: FixtureTransport.knownRoutes)
    let base = "https://api.openai.com/v1/organization"
    for (path, marker) in [("/projects", "proj_fixture"), ("/projects/proj_fixture/api_keys", "key_fixture_a1b2"),
                           ("/usage/completions", "page2"), ("/costs", "organization.costs.result"),
                           ("/usage/completions?start_time=1&page=page2", "1794308400")] {
      let url = try #require(URL(string: base + path))
      let response = try await transport.send(HTTPRequest(url: url))
      #expect(response.status == 200 && utf8Text(response.body).contains(marker), "\(path)")
    }
    let odd = try #require(URL(string: base + "/usage/completions?page=..%2Fx"))
    #expect(FixtureTransport.pageCase(odd) == nil)
  }
}

/// 14 § Stage 3.1 step 6: `app.network_changed {online, interface}` on each transition, not on the first status.
@Suite struct NetworkMonitorTests {
  @Test("transitions are yielded and logged; the first status and repeats are not logged")
  func transitions() async throws {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    var transitions = NetworkTransitions(logPipeline: pipeline)
    let wifi = NetworkStatus(online: true, interface: "wifi")
    let offline = NetworkStatus(online: false, interface: "none")
    let wired = NetworkStatus(online: true, interface: "wired")
    let changed = [wifi, wifi, offline, wired, wired].map { transitions.update($0) }
    #expect(changed == [true, false, true, true, false])
    await pipeline.drain()
    let records = await sink.records.filter { $0.evt == .appNetworkChanged }
    #expect(records.map(\.ctx) == [
      ["online": .bool(false), "interface": .string("none")],
      ["online": .bool(true), "interface": .string("wired")]
    ])
    #expect(records.allSatisfy { $0.lvl == .info && $0.cat == .app })
  }

  @Test("interface names (Q-026)")
  func interfaceNames() {
    let table: [([NWInterface.InterfaceType], String)] = [
      ([.wifi], "wifi"), ([.wiredEthernet, .wifi], "wired"), ([.cellular], "cellular"), ([.loopback], "loopback"),
      ([.other], "other"), ([], "none")
    ]
    for (interfaces, name) in table {
      #expect(NWPathMonitorAdapter.status(online: true, interfaces: interfaces).interface == name)
    }
    #expect(NWPathMonitorAdapter.status(online: false, interfaces: []) == NetworkStatus(online: false, interface: "none"))
  }

  @Test("NWPathMonitorAdapter yields the current status, and stops when the caller does")
  func adapter() async throws {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    var iterator = NWPathMonitorAdapter(logPipeline: pipeline).statuses().makeAsyncIterator()
    let first = await iterator.next()
    #expect(first != nil)
    await pipeline.drain()
    #expect(await sink.records.filter { $0.evt == .appNetworkChanged }.isEmpty, "the first status is not a transition")
  }
}

/// `FixtureEnvelope.load` on a file that is not there (PM-0.5-2).
@Suite struct FixtureEnvelopeLoadTests {
  @Test("a missing fixture file is unreadable, named by its file name")
  func missingFile() {
    #expect(throws: FixtureEnvelope.LoadError.unreadable("nope.json")) {
      try FixtureEnvelope.load(URL(fileURLWithPath: "/nonexistent/nope.json"))
    }
  }
}

/// Small value paths with no other caller yet (PM-0.5-2).
@Suite struct SmallPathTests {
  @Test("a request without a host has no route: noFixture")
  func noHost() async {
    let transport = FixtureTransport(routes: [])
    await #expect(throws: TransportError.self) {
      try await transport.send(HTTPRequest(url: URL(fileURLWithPath: "/x")))
    }
  }

  @Test("bodies that are not UTF-8 are described by size, in PollError and RawBody")
  func notUTF8() {
    let bytes = Data([0xFF, 0xFE])
    if case .server(_, let body) = PollError.from(HTTPResponse(status: 500, body: bytes)) {
      #expect(body == "<2 bytes, not UTF-8>")
    } else {
      Issue.record("a 500 maps to server")
    }
    #expect(RawBody.redacted(bytes, redactor: Redactor()) == "<2 bytes, not UTF-8>")
  }

  @Test("value types: a balance reading, an integer coding key, the probe's message for auth")
  func values() {
    let reading = BalanceReading(snapshots: [], rawBody: "{}")
    #expect(reading.rawBody == "{}" && reading.snapshots.isEmpty)
    #expect(LenientDecoding.AnyKey(intValue: 3)?.stringValue == "3")
    #expect(OpenAIProbe.message(for: .auth(http: 401, body: "")) == CoreStrings.unexpectedResponse("OpenAI"))
  }
}
