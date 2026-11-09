import Foundation
import Testing
@testable import TokenBeCore

/// The static `Log` API (14 § Stage 0.2 step 8). The only suite that touches the process-wide pipeline.
@Suite(.serialized) struct LogFacadeTests {
  @Test("Log.<level> reaches the configured sinks with the right level, and minimumLevel filters")
  func facade() async throws {
    let capture = CapturingLogSink()
    let clock = TestClock()
    let pipeline = Log.configure(sinks: [capture], clock: clock, version: "facade")
    #expect(Log.current === pipeline)
    Log.minimumLevel = .debug
    Log.debug(.schedTick, cat: .sched, msg: "d")
    Log.info(.pollStart, cat: .poll("openai"), msg: "i", acct: "openai", job: "usage")
    Log.notice(.appNetworkChanged, cat: .app, msg: "n", ctx: ["online": true])
    Log.warn(.pollRetry, cat: .poll("openai"), msg: "w", attempt: 2, dur: .milliseconds(5))
    struct Timeout: Error {}
    Log.error(.pollFailed, cat: .poll("openai"), msg: "e", err: Timeout())
    Log.fault(.dbCorrupt, cat: .db, msg: "f")
    Log.minimumLevel = .info
    #expect(Log.minimumLevel == .info)
    Log.debug(.schedTick, cat: .sched, msg: "filtered")
    await pipeline.drain()
    let records = await capture.records
    #expect(records.map(\.lvl) == [.debug, .info, .notice, .warn, .error, .fault])
    #expect(records.map(\.v) == Array(repeating: "facade", count: 6))
    #expect(records[3].attempt == 2)
    #expect(records[3].durMs == 5)
    #expect(records[4].err?.type == "Timeout")
    #expect(Log.breadcrumbs.snapshot().last?.msg == "filtered")

    let replacement = CapturingLogSink()
    let second = Log.configure(sinks: [replacement], clock: clock, version: "facade-2")
    Log.info(.appLaunch, cat: .app, msg: "to the new pipeline")
    struct Broken: Error {}
    Log.reportSinkFailure(op: "write", path: "/x", error: Broken())
    await second.drain()
    await eventually("two records in the replacement sink") { await replacement.records.count >= 2 }
    #expect(Set(await replacement.events()) == [.appLaunch, .appLogSinkFailed])
    await second.shutdown()
  }
}
