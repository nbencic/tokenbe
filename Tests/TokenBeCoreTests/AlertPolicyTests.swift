import Foundation
import Testing
@testable import TokenBeCore

/// 08 § Notifications, 09 § Alerts (11 `AlertPolicyTests`, 14 § Stage 5.4): transitions into low/critical only,
/// unknown > 24 h, stale > 6 h, the toggles, snooze, one per account per kind per 24 h, quiet hours (wrapping past
/// midnight) held and sent at their end, authorization at the first alert, and E2E-4.
@Suite struct AlertPolicyTests {
  static let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00:00Z
  static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()

  static func summary(_ band: Band, id: String = "acct", provider: ProviderID = .openai) -> AccountSummary {
    var summary = AccountSummary(id: id, provider: provider, label: "OpenAI", mode: .anchored, remainingCents: 900,
                                 estimateBandCents: 200, runwayMin: 86_400 + 3_600, band: band)
    summary.anchorAt = now
    return summary
  }

  static func change(_ from: Band, _ band: Band, id: String = "acct") -> BandRecorder.Transition {
    BandRecorder.Transition(accountID: id, from: from, band: band, trigger: .data)
  }

  static func quietOff() -> AlertSettings {
    var settings = AlertSettings()
    settings.quietHoursEnabled = false
    return settings
  }

  @Test("transitions into low or critical qualify; to a better band, or within critical, do not")
  func transitions() {
    let settings = Self.quietOff()
    func kinds(_ change: BandRecorder.Transition, _ band: Band) -> [AlertNotice.Kind] {
      AlertPolicy.candidates([Self.summary(band)], transitions: [change], settings: settings, now: Self.now).map(\.1)
    }
    #expect(kinds(Self.change(.watch, .low), .low) == [.low])
    #expect(kinds(Self.change(.low, .critical), .critical) == [.critical])
    #expect(kinds(Self.change(.critical, .low), .low).isEmpty)
    #expect(kinds(Self.change(.low, .healthy), .healthy).isEmpty)
    // A transition that is no longer the account's band (it moved on since) does not count.
    #expect(kinds(Self.change(.watch, .low), .watch).isEmpty)
  }

  @Test("unknown with a missing anchor for over 24 h; stale for over 6 h")
  func timeRules() {
    var noAnchor = Self.summary(.unknown)
    noAnchor.anchorAt = nil
    noAnchor.bandSince = Self.now.addingTimeInterval(-AlertPolicy.unknownAfter - 1)
    var young = noAnchor
    young.bandSince = Self.now.addingTimeInterval(-3_600)
    var stale = Self.summary(.healthy, id: "s")
    stale.isStale = true
    stale.freshness[.usage] = Self.now.addingTimeInterval(-AlertPolicy.staleAfter - 1)
    var fresh = stale
    fresh.freshness[.usage] = Self.now.addingTimeInterval(-3_600)
    let picked = AlertPolicy.candidates([noAnchor, young, stale, fresh], transitions: [], settings: Self.quietOff(),
                                        now: Self.now)
    #expect(picked.map(\.1) == [.unknown, .stale])
  }

  @Test("each toggle switches its kind off; a snoozed provider gets nothing until the snooze ends")
  func togglesAndSnooze() {
    var settings = Self.quietOff()
    settings.notifyLow = false
    settings.notifyCritical = false
    #expect(AlertPolicy.candidates([Self.summary(.low)], transitions: [Self.change(.watch, .low)], settings: settings,
                                   now: Self.now).isEmpty)
    #expect(AlertPolicy.candidates([Self.summary(.critical)], transitions: [Self.change(.watch, .critical)],
                                   settings: settings, now: Self.now).isEmpty)
    settings = Self.quietOff()
    settings.snoozedUntil[.openai] = Self.now.addingTimeInterval(60)
    #expect(AlertPolicy.candidates([Self.summary(.low)], transitions: [Self.change(.watch, .low)], settings: settings,
                                   now: Self.now).isEmpty)
    settings.snoozedUntil[.openai] = Self.now.addingTimeInterval(-60)
    #expect(AlertPolicy.candidates([Self.summary(.low)], transitions: [Self.change(.watch, .low)], settings: settings,
                                   now: Self.now).count == 1)
    var off = Self.quietOff()
    off.notifyUnknown = false
    off.notifyStale = false
    var stale = Self.summary(.unknown)
    stale.anchorAt = nil
    stale.bandSince = .distantPast
    stale.isStale = true
    stale.freshness[.usage] = .distantPast
    #expect(AlertPolicy.candidates([stale], transitions: [], settings: off, now: Self.now).isEmpty)
  }

  @Test("quiet hours: 23:00–07:00 wraps past midnight; same start and end means none; off means none")
  func quietHours() {
    let settings = AlertSettings()
    func at(_ hour: Int, _ minute: Int = 0) -> Date {
      Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: hour, minute: minute)) ?? Self.now
    }
    #expect(AlertPolicy.isQuiet(at(23), settings: settings, calendar: Self.utc))
    #expect(AlertPolicy.isQuiet(at(2), settings: settings, calendar: Self.utc))
    #expect(AlertPolicy.isQuiet(at(6, 59), settings: settings, calendar: Self.utc))
    #expect(!AlertPolicy.isQuiet(at(7), settings: settings, calendar: Self.utc))
    #expect(!AlertPolicy.isQuiet(at(22, 59), settings: settings, calendar: Self.utc))
    var day = settings
    day.quietStart = 9 * 60
    day.quietEnd = 17 * 60
    #expect(AlertPolicy.isQuiet(at(12), settings: day, calendar: Self.utc))
    #expect(!AlertPolicy.isQuiet(at(18), settings: day, calendar: Self.utc))
    day.quietEnd = day.quietStart
    #expect(!AlertPolicy.isQuiet(at(12), settings: day, calendar: Self.utc))
    #expect(!AlertPolicy.isQuiet(at(23), settings: Self.quietOff(), calendar: Self.utc))
    #expect(AlertSettings.minutes("07:30") == 450)
    #expect(AlertSettings.minutes("24:00") == nil)
    #expect(AlertSettings.minutes("x") == nil)
  }

  @Test("08's body copy for each kind")
  func copy() {
    #expect(AlertPolicy.notice(Self.summary(.critical), kind: .critical, hideCents: true).body
            == "OpenAI: 25 h of runway left (\u{2248} $9 \u{00B1} 2).")
    var direct = Self.summary(.low)
    direct.mode = .direct
    direct.runwayMin = 3 * 86_400
    #expect(AlertPolicy.notice(direct, kind: .low, hideCents: true).body == "OpenAI: ~3 d of runway left ($9).")
    var none = Self.summary(.critical)
    none.remainingCents = nil
    none.runwayMin = nil
    #expect(AlertPolicy.notice(none, kind: .critical, hideCents: true).body == "OpenAI: < 1 h of runway left.")
    #expect(AlertPolicy.notice(none, kind: .unknown, hideCents: true).body == "OpenAI: set an anchor to see runway.")
    #expect(AlertPolicy.notice(none, kind: .stale, hideCents: true).body == "OpenAI: no fresh data for over 6 h.")
    #expect(AlertPolicy.notice(none, kind: .test, hideCents: true).title == "TokenBe")
  }

  // MARK: - AlertCenter

  struct Harness {
    let store: StoreHarness
    let notifier: RecordingNotifier
    let center: AlertCenter

    init(allow: Bool = true) throws {
      store = try StoreHarness()
      notifier = RecordingNotifier(allow: allow)
      center = AlertCenter(notifier: notifier, logPipeline: store.pipeline)
    }
  }

  @Test("E2E-4: a fixture driven to critical gives exactly one notification; back to healthy gives none")
  func endToEnd() async throws {
    let repository = try await OpenAIHarness()
    let recorder = BandRecorder(store: repository.repository, logPipeline: repository.store.pipeline)
    let harness = try Harness()
    let settings = Self.quietOff()
    for (band, offset) in [(Band.healthy, 0.0), (.critical, 60), (.critical, 120), (.healthy, 180)] {
      let now = Self.now.addingTimeInterval(offset)
      var summary = Self.summary(band)
      summary.id = OpenAIHarness.account.id
      let changes = await recorder.record([summary], persisted: [], trigger: .data, now: now)
      await harness.center.process([summary], transitions: changes, settings: settings, now: now)
    }
    let notices = await harness.notifier.notices
    #expect(notices.map(\.kind) == [.critical])
    #expect(await harness.notifier.authorizationRequests == 1)
    let sent = await harness.store.records(.uiNotificationSent)
    #expect(sent.count == 1)
    #expect(sent.first?.acct == "openai")
    #expect(sent.first?.ctx["band"] == "critical")
    #expect(sent.first?.ctx["suppressed_by_quiet_hours"] == false)
  }

  @Test("one per account per kind per 24 h")
  func dedupe() async throws {
    let harness = try Harness()
    let settings = Self.quietOff()
    for offset in [0.0, 3_600, AlertPolicy.dedupeWindow + 1] {
      await harness.center.process([Self.summary(.critical)], transitions: [Self.change(.low, .critical)],
                                   settings: settings, now: Self.now.addingTimeInterval(offset))
    }
    #expect(await harness.notifier.notices.count == 2)
  }

  @Test("quiet hours hold the notice and send it when they end, marked suppressed_by_quiet_hours")
  func quietQueue() async throws {
    let harness = try Harness()
    let night = Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 23, minute: 30)) ?? Self.now
    let morning = night.addingTimeInterval(8 * 3600)
    await harness.center.process([Self.summary(.critical)], transitions: [Self.change(.low, .critical)],
                                 settings: AlertSettings(), now: night, calendar: Self.utc)
    #expect(await harness.notifier.notices.isEmpty)
    await harness.center.process([Self.summary(.critical)], transitions: [], settings: AlertSettings(), now: morning,
                                 calendar: Self.utc)
    #expect(await harness.notifier.notices.count == 1)
    #expect(await harness.store.records(.uiNotificationSent).first?.ctx["suppressed_by_quiet_hours"] == true)
  }

  @Test("denied: ui.notification_denied once, nothing sent; a failed delivery logs ui.error; the test notification")
  func deniedAndFailures() async throws {
    let denied = try Harness(allow: false)
    for offset in [0.0, 60] {
      await denied.center.process([Self.summary(.critical, id: "x\(offset)")],
                                  transitions: [Self.change(.low, .critical, id: "x\(offset)")],
                                  settings: Self.quietOff(), now: Self.now.addingTimeInterval(offset))
    }
    #expect(await denied.store.records(.uiNotificationDenied).count == 1)
    #expect(await denied.notifier.notices.isEmpty)
    #expect(await denied.center.isAuthorized == false)
    #expect(await denied.center.sendTest(nil) == false)

    let failing = try Harness()
    await failing.notifier.setFailing(true)
    #expect(await failing.center.sendTest(Self.summary(.healthy)) == false)
    #expect(await failing.store.records(.uiError).first?.ctx["view"] == "notification")
    await failing.notifier.setFailing(false)
    #expect(await failing.center.sendTest(Self.summary(.healthy)))
    #expect(await failing.notifier.notices.first?.kind == .test)
  }
}
