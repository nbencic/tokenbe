import Foundation
import Testing
@testable import TokenBeCore

/// 11 `NormalizerTests`, the openai rows of `expected/normalize.csv` (14 § Stage 3.4). Each case names a result in
/// a synthetic fixture (`<fixture>/<bucket>/<result>`); the expected classes were computed by hand from 05's table.
@Suite struct NormalizerTests {
  struct Row: Sendable, CustomTestStringConvertible {
    var provider: String
    var fixture: String
    var bucket: Int
    var result: Int
    var expected: TokenClasses
    var testDescription: String { "\(provider) \(fixture)/\(bucket)/\(result)" }
  }

  static func rows() throws -> [Row] {
    let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
    let text = try String(contentsOf: root.appendingPathComponent("Fixtures/expected/normalize.csv"), encoding: .utf8)
    let lines = text.split(separator: "\n").dropFirst()
    return try lines.map { line in
      let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      let path = fields[1].split(separator: "/").map(String.init)
      guard fields.count == 9, path.count == 3, let bucket = Int(path[1]), let result = Int(path[2]) else {
        throw StoreError.notFound("bad normalize.csv line: \(line)")
      }
      let numbers = fields[2...].compactMap { Int64($0) }
      guard numbers.count == 7 else { throw StoreError.notFound("bad numbers: \(line)") }
      return Row(provider: fields[0], fixture: path[0], bucket: bucket, result: result, expected: TokenClasses(
        inputUncached: numbers[0], cacheWrite5m: numbers[1], cacheWrite1h: numbers[2], cacheRead: numbers[3],
        output: numbers[4], reasoning: numbers[5], requests: numbers[6]
      ))
    }
  }

  @Test("the csv has openai rows for every usage fixture result")
  func coverage() throws {
    let rows = try Self.rows().filter { $0.provider == "openai" }
    #expect(rows.count == 4)
    #expect(Set(rows.map(\.fixture)) == ["usage_completions.ok", "usage_completions.page2"])
  }

  @Test("openai usage API → TokenClasses (05 § Normalizers row 1)", arguments: try rows().filter { $0.provider == "openai" })
  func openai(_ row: Row) throws {
    let response = try FixtureEnvelope.load(OpenAIHarness.fixture(row.fixture))
    let page = try LenientDecoding.decode(OpenAIPage<OpenAIUsageResult>.self, from: response.body,
                                          endpoint: "usage_completions").value
    let result = page.data[row.bucket].results[row.result]
    #expect(OpenAINormalizer.classes(result, log: EventLog(pipeline: LogPipeline(sinks: []))) == row.expected)
  }

  @Test("a negative input_uncached is clamped to 0 and logged normalize.negative")
  func negativeClamp() async throws {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    let body = #"{"input_tokens":100,"input_cached_tokens":150,"output_tokens":10}"#
    let result = try LenientDecoding.decode(OpenAIUsageResult.self, from: Data(body.utf8), endpoint: "t").value
    let classes = OpenAINormalizer.classes(result, log: EventLog(pipeline: pipeline))
    #expect(classes == TokenClasses(cacheRead: 150, output: 10))
    await pipeline.drain()
    let record = try #require(await sink.records.first { $0.evt == .normalizeNegative })
    #expect(record.lvl == .warn)
    #expect(record.ctx == ["provider": "openai", "field": "input_uncached", "value": .int(-50)])
  }

  @Test("input_cache_write_tokens absent → 0; num_model_requests absent → 0; nothing negative → no log")
  func defaults() async throws {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    let body = #"{"input_tokens":7,"input_cached_tokens":2,"output_tokens":3}"#
    let result = try LenientDecoding.decode(OpenAIUsageResult.self, from: Data(body.utf8), endpoint: "t").value
    #expect(OpenAINormalizer.classes(result, log: EventLog(pipeline: pipeline))
            == TokenClasses(inputUncached: 5, cacheRead: 2, output: 3))
    await pipeline.drain()
    #expect(await sink.records.isEmpty)
  }

  @Test("cost amounts become cents exactly through Decimal, rounded half up once")
  func cents() throws {
    let cases: [(String, Int64)] = [("0.29", 29), ("0.105", 11), ("0.0049", 0), ("0.9699", 97), ("1.5", 150),
                                    ("12345.675", 1_234_568), ("0.1", 10), ("0.7", 70)]
    for (text, cents) in cases {
      let body = Data(#"{"value":\#(text),"currency":"usd"}"#.utf8)
      let amount = try LenientDecoding.decode(OpenAICostAmount.self, from: body, endpoint: "t").value
      #expect(OpenAIAdapter.cents(amount.value) == cents, "\(text)")
    }
  }
}
