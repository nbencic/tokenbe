import Testing
@testable import TokenBeCore

/// 04 § Startup sequence, D7: steps run in order, one `app.launch {startup_step}` record each; the first failure stops.
/// Stages append their steps here as they implement 04 steps 2–8.
@MainActor @Suite struct StartupSequenceTests {
  /// 04 step names implemented so far, in order.
  static let implementedSteps = ["logging", "database", "accounts"]

  static func harness() -> (LogPipeline, CapturingLogSink) {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    return (pipeline, sink)
  }

  @Test("steps run in 04 order and each logs app.launch with its startup_step")
  func order() async {
    let (pipeline, sink) = Self.harness()
    var ran: [String] = []
    let steps = Self.implementedSteps.map { name in StartupStep(name) { ran.append(name) } }
    let sequence = StartupSequence(steps: steps, logPipeline: pipeline)
    #expect(await sequence.run())
    await pipeline.drain()
    #expect(ran == Self.implementedSteps)
    #expect(sequence.completed == Self.implementedSteps)
    let logged = await sink.records.filter { $0.evt == .appLaunch }.compactMap { record -> String? in
      if case .string(let step) = record.ctx["startup_step"] { return step }
      return nil
    }
    #expect(logged == Self.implementedSteps)
  }

  @Test("the first failing step is logged at error and stops the sequence")
  func stopsOnFailure() async {
    struct Broken: Error {}
    let (pipeline, sink) = Self.harness()
    var ran: [String] = []
    let sequence = StartupSequence(steps: [
      StartupStep("logging") { ran.append("logging") },
      StartupStep("database") { throw Broken() },
      StartupStep("accounts") { ran.append("accounts") }
    ], logPipeline: pipeline)
    #expect(await sequence.run() == false)
    await pipeline.drain()
    #expect(ran == ["logging"])
    #expect(sequence.completed == ["logging"])
    let failure = await sink.records.last
    #expect(failure?.lvl == .error)
    #expect(failure?.ctx["startup_step"] == .string("database"))
    #expect(failure?.err?.type == "Broken")
  }
}
