import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 14 § Stage 5.3 step 2 (11 `BandTransitionTests`): `band_state` and `ui.band_change` only on a change, with
/// `inputs_json` in the same statement (V6, injected failure), the first evaluation silent, and system ledger rows
/// never deleted. On the real database.
@Suite struct BandTransitionTests {
  static let now = Date(timeIntervalSince1970: 1_794_312_000)

  struct Harness {
    let store: StoreHarness
    let repository: GRDBRepository
    let recorder: BandRecorder
    let failing = FailingBandStore()

    init(failing: Bool = false) async throws {
      store = try StoreHarness()
      repository = GRDBRepository(database: try await store.open().database)
      try await repository.insertAccount(OpenAIHarness.account)
      recorder = BandRecorder(store: failing ? self.failing : repository, logPipeline: store.pipeline)
    }

    func states() async throws -> [BandStateRecord] {
      try await repository.database.read { db in try BandStateRecord.fetchAll(db) }
    }
  }

  /// A store whose band write fails until `heal()`.
  actor FailingBandStore: BandRepository {
    var failing = true
    var written: [BandStateRecord] = []
    func heal() { failing = false }
    func recordBand(_ state: BandStateRecord) async throws {
      if failing { throw StoreError.notFound("injected") }
      written.append(state)
    }
    func fetchBandStates() async throws -> [BandStateRecord] { written }
  }

  static func summary(_ band: Band, remaining: Int64? = 9_000) -> AccountSummary {
    var summary = AccountSummary(id: OpenAIHarness.account.id, provider: .openai, label: "OpenAI", mode: .anchored,
                                 remainingCents: remaining, estimateBandCents: 5, burn7dCents: 1_000,
                                 runwayMin: 9 * 86_400, band: band)
    summary.dollarFloorCents = 500
    return summary
  }

  @Test("first evaluation inserts the row silently; same band writes nothing; a change writes and logs")
  func onlyOnChange() async throws {
    let harness = try await Harness()
    await harness.recorder.record([Self.summary(.watch)], persisted: [], trigger: .data, now: Self.now)
    var states = try await harness.states()
    #expect(states.map(\.band) == ["watch"])
    #expect(states.first?.since == "2026-11-10T12:00:00.000Z")
    #expect(states.first?.inputsJson == #"{"burn_7d":1000,"burn_today":null,"estimate_band":5,"floor":500,"remaining":9000,"runway_min":777600}"#)
    #expect(await harness.store.records(.uiBandChange).isEmpty)

    await harness.recorder.record([Self.summary(.watch)], persisted: states, trigger: .data,
                                  now: Self.now.addingTimeInterval(60))
    states = try await harness.states()
    #expect(states.first?.since == "2026-11-10T12:00:00.000Z")
    #expect(await harness.store.records(.uiBandChange).isEmpty)

    await harness.recorder.record([Self.summary(.critical, remaining: 100)], persisted: states, trigger: .data,
                                  now: Self.now.addingTimeInterval(120))
    states = try await harness.states()
    #expect(states.map(\.band) == ["critical"])
    #expect(states.first?.inputsJson.contains(#""remaining":100"#) == true)
    let changes = await harness.store.records(.uiBandChange)
    #expect(changes.count == 1)
    #expect(changes.first?.acct == "openai")
    #expect(changes.first?.ctx["from"] == "watch")
    #expect(changes.first?.ctx["to"] == "critical")
    #expect(changes.first?.ctx["trigger"] == "data")
    #expect(changes.first?.ctx["inputs"] == .string(states.first?.inputsJson ?? ""))
  }

  @Test("a fresh recorder seeds from the persisted row (no log after a relaunch)")
  func seededFromPersisted() async throws {
    let harness = try await Harness()
    let persisted = [BandStateRecord(accountId: OpenAIHarness.account.id, band: "low", since: "2026-11-09T00:00:00.000Z",
                                     inputsJson: "{}")]
    await harness.recorder.record([Self.summary(.low)], persisted: persisted, trigger: .clock, now: Self.now)
    #expect(try await harness.states().isEmpty)
    await harness.recorder.record([Self.summary(.healthy)], persisted: persisted, trigger: .settings, now: Self.now)
    let changes = await harness.store.records(.uiBandChange)
    #expect(changes.first?.ctx["from"] == "low")
    #expect(changes.first?.ctx["trigger"] == "settings")
  }

  @Test("a change found at the first evaluation after a launch is logged as trigger launch")
  func launchTrigger() async throws {
    let harness = try await Harness()
    let persisted = [BandStateRecord(accountId: OpenAIHarness.account.id, band: "unknown", since: "x", inputsJson: "{}")]
    await harness.recorder.record([Self.summary(.critical)], persisted: persisted, trigger: .data, now: Self.now)
    #expect(await harness.store.records(.uiBandChange).first?.ctx["trigger"] == "launch")
  }

  @Test("V6: a failed write changes nothing and logs ui.error, no band change; the next evaluation retries")
  func injectedFailure() async throws {
    let harness = try await Harness(failing: true)
    let persisted = [BandStateRecord(accountId: OpenAIHarness.account.id, band: "watch", since: "x", inputsJson: "{}")]
    await harness.recorder.record([Self.summary(.low)], persisted: persisted, trigger: .data, now: Self.now)
    #expect(await harness.store.records(.uiBandChange).isEmpty)
    let errors = await harness.store.records(.uiError)
    #expect(errors.count == 1)
    #expect(errors.first?.ctx["view"] == "band")

    let store = harness.failing
    await store.heal()
    await harness.recorder.record([Self.summary(.low)], persisted: persisted, trigger: .data, now: Self.now)
    #expect(await store.written.map(\.band) == ["low"])
    #expect(await harness.store.records(.uiBandChange).count == 1)
  }

  @Test("deleteUserLedgerEvent deletes user rows only (R7)")
  func deleteUserRowsOnly() async throws {
    let harness = try await Harness()
    for (id, source) in [("u", "user"), ("s", "system")] {
      try await harness.repository.insertLedgerEvent(LedgerEventRecord(
        id: id, accountId: OpenAIHarness.account.id, ts: "2026-11-10T00:00:00.000Z", kind: "anchor", amountCents: 1,
        currency: "USD", note: nil, source: source
      ))
    }
    #expect(try await harness.repository.deleteUserLedgerEvent(id: "s") == false)
    #expect(try await harness.repository.deleteUserLedgerEvent(id: "u") == true)
    #expect(try await harness.repository.deleteUserLedgerEvent(id: "u") == false)
    let left = try await harness.repository.database.read { db in try LedgerEventRecord.fetchAll(db) }
    #expect(left.map(\.id) == ["s"])

    let memory = MemoryRepository()
    try await memory.insertLedgerEvent(LedgerEventRecord(id: "m", accountId: "a", ts: "t", kind: "topup",
                                                         amountCents: 1, currency: nil, note: nil, source: "user"))
    #expect(try await memory.deleteUserLedgerEvent(id: "m"))
    try await memory.recordBand(BandStateRecord(accountId: "a", band: "low", since: "t", inputsJson: "{}"))
    #expect(await memory.bands["a"]?.band == "low")
    #expect(try await memory.fetchBandStates().map(\.band) == ["low"])
  }

  @Test("top-ups log ledger.topup; the observation carries ledger, balances, band_state and the anchor day")
  func ledgerActionsAndObservation() async throws {
    let harness = try await OpenAIHarness()
    let lifecycle = AccountLifecycle(repository: harness.repository, keyStore: harness.keys,
                                     registry: ProviderRegistry(adapters: [harness.adapter]),
                                     transport: harness.transport, logPipeline: harness.store.pipeline,
                                     now: harness.date.provider)
    try await lifecycle.setAnchor(OpenAIHarness.account, cents: 10_000,
                                  asOf: Date(timeIntervalSince1970: 1_794_222_000))   // 2026-11-09T11:00:00Z
    try await lifecycle.addTopUp(OpenAIHarness.account, cents: 2_500, note: String(repeating: "n", count: 200))
    #expect(await harness.records(.ledgerTopup).first?.ctx["amount_cents"] == 2_500)
    try await harness.repository.recordBand(BandStateRecord(accountId: OpenAIHarness.account.id, band: "low",
                                                            since: "2026-11-10T00:00:00.000Z", inputsJson: "{}"))
    try await harness.database.write("balance") { db in
      try BalanceSnapshotRecord(accountId: OpenAIHarness.account.id, ts: "2026-11-10T01:00:00.000Z", currency: "USD",
                                amountCents: 1, grantedCents: nil, toppedUpCents: nil, isAvailable: nil).insert(db)
      try BalanceSnapshotRecord(accountId: OpenAIHarness.account.id, ts: "2026-11-10T02:00:00.000Z", currency: "USD",
                                amountCents: 2, grantedCents: nil, toppedUpCents: nil, isAvailable: nil).insert(db)
    }
    await harness.on(OpenAIHarness.usage, "usage_completions.ok", "usage_completions.page2")
    #expect(await harness.run(.usage) == .succeeded(rows: 4))
    var stream = harness.repository.observeSummaryInputs().makeAsyncIterator()
    let inputs = try #require(await stream.next())
    #expect(inputs.ledgerEvents.map(\.kind) == ["anchor", "topup"])
    #expect(inputs.ledgerEvents.last?.note?.count == AccountLifecycle.noteLimit)
    #expect(inputs.balances.map(\.amountCents) == [2])
    #expect(inputs.bandStates.map(\.band) == ["low"])
    // The anchor (11:00 on 11-09) leaves the 11:00 bucket of that day: gpt-4o-mini, 0 cents.
    #expect(inputs.anchorDayUsage.map(\.day) == ["2026-11-09"])
    #expect(inputs.anchorDayUsage.map(\.estCents) == [0])
  }
}
