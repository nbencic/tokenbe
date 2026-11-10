import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 3.4 Tests, `AdapterTests/OpenAI`: each synthetic fixture case → exact rows; the probe's messages for
/// 401/403/429/500; the paging cursor survives a failure between pages; `last_raw` is redacted and ≤ 64 KiB;
/// unknown keys are logged once per day.
@Suite struct OpenAITests {
  typealias Harness = OpenAIHarness
  static let fetchedAt = "2026-11-10T12:00:00.000Z"

  /// `grain` is model, provider key id and service tier.
  static func usageRow(_ start: String, _ grain: [String], _ classes: TokenClasses,
                       provisional: Bool) -> UsageBucketRecord {
    UsageBucketRecord(
      accountId: Harness.account.id, bucketStart: start, bucketWidth: "1h", model: grain[0], providerKeyId: grain[1],
      serviceTier: grain[2], source: "provider", inputUncached: classes.inputUncached, cacheWrite5m: classes.cacheWrite5m,
      cacheWrite1h: classes.cacheWrite1h, cacheRead: classes.cacheRead, output: classes.output,
      reasoning: classes.reasoning, requests: classes.requests, estCostCents: nil, unpriced: false,
      provisional: provisional, fetchedAt: fetchedAt
    )
  }

  /// `usage_completions.ok` + `.page2`, by hand from the fixtures and 05's row 1 (sorted like `fetchUsageBuckets`).
  static let usageRows = [
    usageRow("2026-11-09T10:00:00.000Z", ["gpt-4o-2024-08-06", "key_fixture_a1b2", "default"],
             TokenClasses(inputUncached: 1000, cacheRead: 200, output: 300, requests: 4), provisional: false),
    usageRow("2026-11-09T10:00:00.000Z", ["gpt-4o-mini", "key_fixture_c3d4", "default"],
             TokenClasses(inputUncached: 500, cacheWrite5m: 50, output: 80, requests: 2), provisional: false),
    usageRow("2026-11-09T11:00:00.000Z", ["gpt-4o-mini", "key_fixture_a1b2", "flex"],
             TokenClasses(cacheRead: 150, output: 10, requests: 1), provisional: false),
    usageRow("2026-11-10T11:00:00.000Z", ["gpt-4o-2024-08-06", "key_fixture_a1b2", "default"],
             TokenClasses(inputUncached: 40, cacheRead: 10, output: 5, requests: 1), provisional: true)
  ]

  static func cost(_ day: String, _ kind: String, _ key: String, _ cents: Int64, provisional: Bool = false)
    -> CostBucketRecord {
    CostBucketRecord(accountId: Harness.account.id, day: day, groupKind: kind, groupKey: key, amountCents: cents,
                     currency: "USD", provisional: provisional, fetchedAt: fetchedAt)
  }

  /// `costs.ok` by hand: per day, sums per key and per line item, `total` = Σ results, each rounded half up once.
  static let costRows = [
    cost("2026-11-08", "api_key_id", "key_fixture_c3d4", 150),
    cost("2026-11-08", "line_item", "gpt-4o-mini, input", 150),
    cost("2026-11-08", "total", "", 150),
    cost("2026-11-09", "api_key_id", "", 0),
    cost("2026-11-09", "api_key_id", "key_fixture_a1b2", 86),
    cost("2026-11-09", "api_key_id", "key_fixture_c3d4", 11),
    cost("2026-11-09", "line_item", "gpt-4o-2024-08-06, input", 29),
    cost("2026-11-09", "line_item", "gpt-4o-2024-08-06, output", 57),
    cost("2026-11-09", "line_item", "gpt-4o-mini, input", 11),
    cost("2026-11-09", "line_item", "gpt-4o-mini, output", 0),
    cost("2026-11-09", "total", "", 97),
    cost("2026-11-10", "api_key_id", "key_fixture_a1b2", 1, provisional: true),
    cost("2026-11-10", "line_item", "gpt-4o-mini, output", 1, provisional: true),
    cost("2026-11-10", "total", "", 1, provisional: true)
  ]

  static func query(_ request: HTTPRequest) -> String {
    URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
  }

  // MARK: - Keys

  @Test("keys: projects → api_keys upserts provider_key rows with name, redacted, project_id and status")
  func keys() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, "projects.ok")
    await env.on(Harness.apiKeys, "api_keys.ok")
    #expect(await env.run(.keys) == .succeeded(rows: 2))
    let rows = try await env.repository.fetchProviderKeys(accountID: Harness.account.id)
    #expect(rows == [
      ProviderKeyRecord(accountId: Harness.account.id, providerKeyId: "key_fixture_a1b2", name: "Production",
                        redacted: "sk-FIXTURE-openai-a1b2", projectId: "proj_fixture", workspaceId: nil, status: "active",
                        firstSeenAt: Self.fetchedAt, lastSeenAt: Self.fetchedAt),
      ProviderKeyRecord(accountId: Harness.account.id, providerKeyId: "key_fixture_c3d4", name: "Staging",
                        redacted: "sk-FIXTURE-openai-c3d4", projectId: "proj_fixture", workspaceId: nil, status: "active",
                        firstSeenAt: Self.fetchedAt, lastSeenAt: Self.fetchedAt)
    ])
    let calls = await env.transport.calls
    #expect(calls.map { Self.query($0) } == ["limit=100", "limit=100"])
    #expect(calls.allSatisfy { $0.headers["Authorization"] == "Bearer \(env.key)" && $0.url.host() == "api.openai.com" })
    // A later poll keeps first_seen_at and refreshes last_seen_at.
    env.date.set(Harness.now.addingTimeInterval(3600))
    #expect(await env.run(.keys) == .succeeded(rows: 2))
    let again = try await env.repository.fetchProviderKeys(accountID: Harness.account.id)
    #expect(again.map(\.firstSeenAt) == [Self.fetchedAt, Self.fetchedAt])
    #expect(again.map(\.lastSeenAt) == ["2026-11-10T13:00:00.000Z", "2026-11-10T13:00:00.000Z"])
    let state = try await env.state(.keys)
    #expect(state.lastSuccessAt == "2026-11-10T13:00:00.000Z" && state.consecutiveFailures == 0)
  }

  // MARK: - Usage

  @Test("usage: two pages → exact usage_bucket rows, 02's query, cursor cleared, provisional by bucket age")
  func usageTwoPages() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, "usage_completions.ok", "usage_completions.page2")
    #expect(await env.run(.usage) == .succeeded(rows: 4))
    #expect(try await env.repository.fetchUsageBuckets(accountID: Harness.account.id) == Self.usageRows)
    let groups = "group_by%5B%5D=api_key_id&group_by%5B%5D=model&group_by%5B%5D=service_tier"
    #expect(await env.transport.calls.map { Self.query($0) } == [
      "start_time=1794139200&bucket_width=1h&\(groups)",
      "start_time=1794139200&bucket_width=1h&\(groups)&page=page2"
    ])
    let state = try await env.state(.usage)
    #expect(state.cursor == nil && state.lastSuccessAt == Self.fetchedAt)
    #expect(await env.records(.pollOk).last?.ctx["rows"] == .int(4))
  }

  @Test("usage: an empty page writes nothing and succeeds")
  func usageEmpty() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, "usage_completions.empty")
    #expect(await env.run(.usage) == .succeeded(rows: 0))
    #expect(try await env.repository.fetchUsageBuckets(accountID: Harness.account.id).isEmpty)
    #expect(await env.transport.calls.count == 1)
  }

  @Test("usage: the cursor is saved after each page, so a failure between pages resumes at the next page")
  func cursorSurvivesFailure() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, .fixture(Harness.fixture("usage_completions.ok")), Harness.status(500))
    let first = Task { await env.run(.usage) }
    for _ in 0..<3 {
      await env.clock.waitForSleepers()
      env.clock.advance(by: .seconds(60))
    }
    #expect(await first.value == .failed("server"))
    var state = try await env.state(.usage)
    #expect(state.cursor == "1794139200 page2")
    #expect(state.consecutiveFailures == 1 && state.lastErrorClass == "server")
    #expect(try await env.repository.fetchUsageBuckets(accountID: Harness.account.id) == Array(Self.usageRows.prefix(3)))

    // Five minutes later: the resumed run repeats page 1's start_time with the saved page token.
    env.date.set(Harness.now.addingTimeInterval(300))
    await env.transport.replace("GET", Harness.usage, .fixture(Harness.fixture("usage_completions.page2")))
    #expect(await env.run(.usage) == .succeeded(rows: 1))
    #expect(Self.query(try #require(await env.transport.calls.last)).hasSuffix("&page=page2"))
    #expect(Self.query(try #require(await env.transport.calls.last)).hasPrefix("start_time=1794139200&"))
    state = try await env.state(.usage)
    #expect(state.cursor == nil && state.consecutiveFailures == 0)
    #expect(try await env.repository.fetchUsageBuckets(accountID: Harness.account.id).count == 4)
    #expect(await env.records(.pollOk).last?.ctx["cursor"] == .string("1794139200 page2"))
  }

  // MARK: - Cost

  @Test("cost: 7 days grouped by api_key_id and line_item → per-kind rows plus one total per day, in cents")
  func cost() async throws {
    let env = try await Harness()
    await env.on(Harness.costs, "costs.ok")
    #expect(await env.run(.cost) == .succeeded(rows: Self.costRows.count))
    #expect(try await env.repository.fetchCostBuckets(accountID: Harness.account.id) == Self.costRows)
    #expect(Self.query(try #require(await env.transport.calls.first))
            == "start_time=1793664000&group_by%5B%5D=api_key_id&group_by%5B%5D=line_item")
  }

  @Test("cost: a re-fetch replaces each returned day whole; other days stay")
  func costRefetch() async throws {
    let env = try await Harness()
    await env.on(Harness.costs, "costs.ok")
    #expect(await env.run(.cost) == .succeeded(rows: 14))
    let refetched = """
      {"object":"page","has_more":false,"next_page":null,"data":[{"object":"bucket","start_time":1794268800,
      "end_time":1794355200,"results":[{"object":"organization.costs.result","amount":{"value":0.25,"currency":"usd"},
      "line_item":"gpt-4o-mini, input","project_id":"proj_fixture","api_key_id":"key_fixture_c3d4","api_source":null}]}]}
      """
    await env.transport.replace("GET", Harness.costs, Harness.ok(refetched))
    #expect(await env.run(.cost) == .succeeded(rows: 3))
    let rows = try await env.repository.fetchCostBuckets(accountID: Harness.account.id)
    #expect(rows.filter { $0.day == "2026-11-10" } == [
      Self.cost("2026-11-10", "api_key_id", "key_fixture_c3d4", 25, provisional: true),
      Self.cost("2026-11-10", "line_item", "gpt-4o-mini, input", 25, provisional: true),
      Self.cost("2026-11-10", "total", "", 25, provisional: true)
    ])
    #expect(rows.filter { $0.day != "2026-11-10" } == Self.costRows.filter { $0.day != "2026-11-10" })
  }

  @Test("cost: pages are followed until has_more is false; a day with no results gets a zero total")
  func costPaging() async throws {
    let env = try await Harness()
    let first = """
      {"object":"page","has_more":true,"next_page":"c2","data":[{"object":"bucket","start_time":1794009600,
      "end_time":1794096000,"results":[]}]}
      """
    await env.on(Harness.costs, Harness.ok(first), .fixture(Harness.fixture("costs.ok")))
    #expect(await env.run(.cost) == .succeeded(rows: 15))
    #expect(try await env.repository.fetchCostBuckets(accountID: Harness.account.id).first == Self.cost("2026-11-07", "total", "", 0))
    #expect(Self.query(try #require(await env.transport.calls.last)).hasSuffix("&page=c2"))
  }

  // MARK: - last_raw and unknown keys

  @Test("last_raw is redacted and at most 64 KiB")
  func lastRawRedactedAndCapped() async throws {
    let env = try await Harness()
    let padding = String(repeating: "p", count: 70_000)
    let body = #"{"object":"page","data":[],"has_more":false,"next_page":null,"#
      + #""note":"\#(env.key)","padding":"\#(padding)"}"#
    await env.on(Harness.usage, Harness.ok(body))
    #expect(await env.run(.usage) == .succeeded(rows: 0))
    let raw = try #require(try await env.state(.usage).lastRaw)
    #expect(raw.count <= RawBody.limit)
    let text = utf8Text(raw)
    #expect(!text.contains(env.key) && text.contains(Redactor.keyMarker))
    #expect(!(await env.allLines()).contains(env.key))
  }

  @Test("unknown keys: poll.unknown_keys and normalize.unknown_keys once per day, again the next day")
  func unknownKeysOncePerDay() async throws {
    let env = try await Harness()
    let body = """
      {"object":"page","has_more":false,"next_page":null,"first_id":"x","data":[{"object":"bucket",
      "start_time":1794218400,"end_time":1794222000,"results":[{"input_tokens":1,"input_cached_tokens":0,
      "output_tokens":1,"num_model_requests":1,"model":"gpt-4o-mini","api_key_id":"k","service_tier":"default",
      "object":"organization.usage.completions.result"}]}]}
      """
    await env.on(Harness.usage, Harness.ok(body))
    #expect(await env.run(.usage) == .succeeded(rows: 1))
    #expect(await env.run(.usage) == .succeeded(rows: 1))
    var poll = await env.records(.pollUnknownKeys)
    var normalize = await env.records(.normalizeUnknownKeys)
    #expect(poll.count == 1 && normalize.count == 1)
    #expect(poll.first?.ctx["keys"] == "first_id" && poll.first?.job == "usage" && poll.first?.acct == "openai")
    #expect(normalize.first?.ctx["keys"] == "data[].results[].object")
    #expect(normalize.first?.ctx["provider"] == "openai")
    env.date.set(Harness.now.addingTimeInterval(86400))
    #expect(await env.run(.usage) == .succeeded(rows: 1))
    poll = await env.records(.pollUnknownKeys)
    normalize = await env.records(.normalizeUnknownKeys)
    #expect(poll.count == 2 && normalize.count == 2)
  }

  @Test("a missing required field fails as decode: no retry, poll.schema_drift, last_raw keeps the body")
  func decodeFailure() async throws {
    let env = try await Harness()
    let body = """
      {"object":"page","has_more":false,"next_page":null,"data":[{"object":"bucket","start_time":1794218400,
      "end_time":1794222000,"results":[{"input_tokens":1,"input_cached_tokens":0}]}]}
      """
    await env.on(Harness.usage, Harness.ok(body))
    #expect(await env.run(.usage) == .failed("decode"))
    #expect(await env.transport.calls.count == 1)
    let drift = try #require(await env.records(.pollSchemaDrift).first)
    #expect(drift.ctx["missing_keys"] == "output_tokens")
    #expect(drift.ctx["path"] == "usage_completions: data[].results[]")
    let state = try await env.state(.usage)
    #expect(state.lastErrorClass == "decode")
    #expect(utf8Text(try #require(state.lastRaw)).contains("input_cached_tokens"))
  }
}

/// The probe half of `AdapterTests/OpenAI` (02 § openai Probe; messages Q-029).
@Suite struct OpenAIProbeTests {
  typealias Harness = OpenAIHarness

  static func query(_ request: HTTPRequest) -> String { OpenAITests.query(request) }

  @Test("probe: four steps pass → 02's capabilities, the discovered keys, redacted bodies, no message")
  func probeOK() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, "projects.ok")
    await env.on(Harness.apiKeys, "api_keys.ok")
    await env.on(Harness.usage, "usage_completions.empty")
    await env.on(Harness.costs, "costs.ok")
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == nil)
    #expect(result.capabilities == OpenAIAdapter.capabilities)
    #expect(result.discoveredKeys.map(\.providerKeyID) == ["key_fixture_a1b2", "key_fixture_c3d4"])
    #expect(result.discoveredKeys.allSatisfy { $0.projectID == "proj_fixture" })
    #expect(Set(result.rawBodiesRedacted.keys) == ["projects", "api_keys", "usage_completions", "costs"])
    #expect(result.rawBodiesRedacted.values.allSatisfy { !$0.contains("sk-") })
    #expect(await env.transport.callOrder == [
      "GET \(Harness.projects)", "GET \(Harness.apiKeys)", "GET \(Harness.usage)", "GET \(Harness.costs)"
    ])
    let usageQuery = Self.query(try #require(await env.transport.calls.first { $0.url.path() == Harness.usage }))
    #expect(usageQuery.contains("bucket_width=1h") && usageQuery.hasSuffix("&limit=1"))
  }

  struct ProbeCase: Sendable, CustomTestStringConvertible {
    var name: String
    var path: String
    var fixture: String
    var message: String
    var testDescription: String { name }
  }

  static let probeFailures = [
    ProbeCase(name: "401 on step 1", path: Harness.projects, fixture: "projects.401", message: CoreStrings.OpenAI.notAdminKey),
    ProbeCase(name: "429 on step 3", path: Harness.usage, fixture: "usage_completions.429",
              message: "OpenAI is limiting requests right now. Try again in a minute."),
    ProbeCase(name: "500 on step 3", path: Harness.usage, fixture: "usage_completions.500",
              message: "OpenAI returned a server error (HTTP 500). Try again later.")
  ]

  @Test("probe: 401/429/500 end the probe with their human message", arguments: probeFailures)
  func probeFailure(_ probe: ProbeCase) async throws {
    let env = try await Harness()
    await env.on(Harness.projects, "projects.ok")
    await env.on(Harness.apiKeys, "api_keys.ok")
    await env.on(Harness.usage, "usage_completions.empty")
    await env.on(Harness.costs, "costs.ok")
    await env.transport.replace("GET", probe.path, .fixture(Harness.fixture(probe.fixture)))
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == probe.message)
    #expect(await env.transport.calls.count == (probe.path == Harness.projects ? 1 : 3))
  }

  @Test("probe: 401 message is 02's sentence, word for word")
  func adminKeyCopy() {
    #expect(CoreStrings.OpenAI.notAdminKey == "This is not an Admin key. Create one at platform.openai.com → Settings → Organization → Admin keys (Organization Owner only).")
  }

  @Test("probe: 403 on step 1 fails with the missing-scope message")
  func probeForbiddenStepOne() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, Harness.status(403, "no scope"))
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == CoreStrings.OpenAI.missingScope)
    #expect(result.rawBodiesRedacted["projects"] == "no scope")
  }

  @Test("probe: 403 on step 4 turns cost off, keeps the body, and still passes")
  func probeForbiddenCost() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, "projects.ok")
    await env.on(Harness.apiKeys, "api_keys.ok")
    await env.on(Harness.usage, "usage_completions.empty")
    await env.on(Harness.costs, "costs.403")
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == nil)
    var expected = OpenAIAdapter.capabilities
    expected.cost = false
    #expect(result.capabilities == expected)
    #expect(result.rawBodiesRedacted["costs"]?.contains("synthetic 403") == true)
  }

  @Test("probe: offline ends the probe with the unreachable message; a key echoed in a body is redacted")
  func probeOfflineAndRedaction() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, .failure(.urlError(URLError(.notConnectedToInternet))))
    let offline = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(offline.humanMessage == "Could not reach OpenAI. Check your internet connection and try again.")

    let echo = try await Harness()
    await echo.on(Harness.projects, Harness.status(401, "bad key \(echo.key)"))
    let refused = await echo.adapter.probe(key: echo.key, transport: echo.transport)
    #expect(refused.rawBodiesRedacted["projects"] == "bad key \(Redactor.keyMarker)")
  }
}
