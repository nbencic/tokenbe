import Foundation
import Testing
@testable import TokenBeCore

/// OpenAI adapter edges the fixture cases do not reach (PM-0.5-2): probe refusals per step, undecodable bodies,
/// unexpected statuses; usage rows merged on a null grouping field; the costs page cap and a split UTC day.
@Suite struct OpenAIEdgeTests {
  typealias Harness = OpenAIHarness

  static let empty = StubTransport.Answer.fixture(Harness.fixture("usage_completions.empty"))

  @Test("probe: 403 on usage turns usage and per-key usage off and still passes")
  func probeUsageRefused() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, "projects.ok")
    await env.on(Harness.apiKeys, "api_keys.ok")
    await env.on(Harness.usage, Harness.status(403, "no usage scope"))
    await env.on(Harness.costs, "costs.ok")
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == nil)
    #expect(result.capabilities.usage == false && result.capabilities.perKeyUsage == false)
  }

  @Test("probe: 403 on a project's keys turns key names off; a 500 there ends the probe")
  func probeKeys() async throws {
    let refused = try await Harness()
    await refused.on(Harness.projects, "projects.ok")
    await refused.on(Harness.apiKeys, Harness.status(403, "no"))
    await refused.on(Harness.usage, Self.empty)
    await refused.on(Harness.costs, "costs.ok")
    let passed = await refused.adapter.probe(key: refused.key, transport: refused.transport)
    #expect(passed.humanMessage == nil && passed.capabilities.keyNames == false)

    let broken = try await Harness()
    await broken.on(Harness.projects, "projects.ok")
    await broken.on(Harness.apiKeys, Harness.status(500, "down"))
    let failed = await broken.adapter.probe(key: broken.key, transport: broken.transport)
    #expect(failed.humanMessage == CoreStrings.serverError("OpenAI", status: 500))
  }

  @Test("probe: a 500 on costs ends the probe with its message")
  func probeCostFails() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, "projects.ok")
    await env.on(Harness.apiKeys, "api_keys.ok")
    await env.on(Harness.usage, Self.empty)
    await env.on(Harness.costs, Harness.status(500, "down"))
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == CoreStrings.serverError("OpenAI", status: 500))
  }

  @Test("probe: undecodable projects or api_keys bodies end with the unreadable message and poll.schema_drift")
  func probeUndecodable() async throws {
    let projects = try await Harness()
    await projects.on(Harness.projects, Harness.ok(#"{"object":"list"}"#))
    let first = await projects.adapter.probe(key: projects.key, transport: projects.transport)
    #expect(first.humanMessage == CoreStrings.unexpectedResponse("OpenAI"))
    #expect(await projects.records(.pollSchemaDrift).first?.job == "probe")

    let keys = try await Harness()
    await keys.on(Harness.projects, "projects.ok")
    await keys.on(Harness.apiKeys, Harness.ok(#"{"object":"list"}"#))
    let second = await keys.adapter.probe(key: keys.key, transport: keys.transport)
    #expect(second.humanMessage == CoreStrings.unexpectedResponse("OpenAI"))
  }

  @Test("probe messages: an unexpected HTTP status is named; other provider rules read as unrecognized")
  func probeMessages() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, Harness.status(404, "missing"))
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == CoreStrings.unexpectedStatus("OpenAI", status: 404))
    #expect(OpenAIProbe.message(for: .providerRule("odd")) == CoreStrings.unexpectedResponse("OpenAI"))
    #expect(OpenAIProbe.message(for: .rateLimited(retryAfter: nil)) == CoreStrings.rateLimited("OpenAI"))
  }

  @Test("usage: two results on one row key (null grouping fields) are summed into one row (V2)")
  func usageMerge() async throws {
    let env = try await Harness()
    let result = #"{"input_tokens":100,"input_cached_tokens":0,"output_tokens":10,"num_model_requests":1,"#
      + #""api_key_id":null,"model":null,"service_tier":null}"#
    let body = #"{"object":"page","data":[{"object":"bucket","start_time":1794218400,"end_time":1794222000,"#
      + #""results":[\#(result),\#(result)]}],"has_more":false,"next_page":null}"#
    await env.on(Harness.usage, Harness.ok(body))
    #expect(await env.run(.usage) == .succeeded(rows: 1))
    let rows = try await env.repository.fetchUsageBuckets(accountID: Harness.account.id)
    #expect(rows.count == 1)
    #expect(rows.first?.requests == 2)
  }

  @Test("costs: more than 50 pages fails as a provider rule")
  func costPageCap() async throws {
    let env = try await Harness()
    for index in 1...(OpenAIAdapter.maxPages + 1) {
      await env.on(Harness.costs, Harness.ok(#"{"object":"page","data":[],"has_more":true,"next_page":"p\#(index)"}"#))
    }
    #expect(await env.run(.cost) == .failed("provider_rule"))
    #expect(await env.records(.pollProviderRule).first?.ctx["rule"] == "openai_costs_more_than_50_pages")
  }

  @Test("costs: two buckets on one UTC day are one day; a null line_item groups under an empty key")
  func costSameDay() async throws {
    let env = try await Harness()
    let result = #"{"object":"organization.costs.result","amount":{"value":0.5,"currency":"usd"},"line_item":null,"#
      + #""project_id":null,"api_key_id":"key_fixture_c3d4","api_source":null}"#
    let bucket = { (start: Int) in
      #"{"object":"bucket","start_time":\#(start),"end_time":\#(start + 3600),"results":[\#(result)]}"#
    }
    let body = #"{"object":"page","data":[\#(bucket(1_794_096_000)),\#(bucket(1_794_099_600))],"#
      + #""has_more":false,"next_page":null}"#
    await env.on(Harness.costs, Harness.ok(body))
    #expect(await env.run(.cost) == .succeeded(rows: 3))
    let rows = try await env.repository.fetchCostBuckets(accountID: Harness.account.id)
    #expect(Set(rows.map(\.day)).count == 1)
    #expect(rows.first { $0.groupKind == "line_item" }?.groupKey == "")
    #expect(rows.first { $0.groupKind == "total" }?.amountCents == 100)
  }

  @Test("a body that is not JSON decodes to PollError.decode on the body")
  func notJSON() {
    #expect(throws: PollError.self) {
      try LenientDecoding.decode(OpenAIProjectList.self, from: Data("not json".utf8), endpoint: "projects")
    }
    do {
      _ = try LenientDecoding.decode(OpenAIProjectList.self, from: Data("not json".utf8), endpoint: "projects")
    } catch {
      if case .decode(let field, _) = error { #expect(field == "body") } else { Issue.record("\(error)") }
    }
  }
}
