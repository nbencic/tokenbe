import Foundation

/// 09 § Alerts' notification keys, read on the main actor and handed to `AlertCenter`.
public struct AlertSettings: Sendable, Equatable {
  public var notifyLow = true
  public var notifyCritical = true
  public var notifyUnknown = true
  public var notifyStale = true
  public var quietHoursEnabled = true
  /// Minutes after local midnight (`tb.alerts.quietStart` / `quietEnd`, `HH:mm`).
  public var quietStart = 23 * 60
  public var quietEnd = 7 * 60
  /// `tb.alerts.snoozedUntil.<provider>`.
  public var snoozedUntil: [ProviderID: Date] = [:]
  public var hideCents = true

  public init() {}

  @MainActor
  public init(_ settings: Settings) {
    notifyLow = settings.alertsNotifyLow
    notifyCritical = settings.alertsNotifyCritical
    notifyUnknown = settings.alertsNotifyUnknown
    notifyStale = settings.alertsNotifyStale
    quietHoursEnabled = settings.alertsQuietHoursEnabled
    quietStart = Self.minutes(settings.alertsQuietStart) ?? quietStart
    quietEnd = Self.minutes(settings.alertsQuietEnd) ?? quietEnd
    for provider in ProviderID.allCases where settings.snoozedUntil(provider) > 0 {
      snoozedUntil[provider] = Date(timeIntervalSince1970: settings.snoozedUntil(provider))
    }
    hideCents = settings.uiHideCents
  }

  /// `HH:mm` → minutes after midnight; nil when it does not parse.
  public static func minutes(_ text: String) -> Int? {
    let parts = text.split(separator: ":")
    guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]), (0..<24).contains(hours),
          (0..<60).contains(minutes) else { return nil }
    return hours * 60 + minutes
  }

  /// The settings that change what is notified.
  public static let keys: Set<SettingsKey> = [.alertsNotifyLow, .alertsNotifyCritical, .alertsNotifyUnknown,
                                              .alertsNotifyStale, .alertsQuietHoursEnabled, .alertsQuietStart,
                                              .alertsQuietEnd]
}

/// 08 § Notifications (14 § Stage 5.4 step 2): what deserves a notification.
/// - a band transition INTO `low` or `critical` (never to a better band);
/// - `unknown` because the anchor is missing, for more than 24 h;
/// - `stale` for more than 6 h.
/// Each is switched by its 09 toggle; snoozed accounts are skipped; at most one per account per kind per 24 h.
public enum AlertPolicy {
  public static let unknownAfter: TimeInterval = 24 * 3600
  public static let staleAfter: TimeInterval = 6 * 3600
  public static let dedupeWindow: TimeInterval = 24 * 3600
  public static let snooze: TimeInterval = 24 * 3600

  /// The kinds each account qualifies for now.
  public static func candidates(_ summaries: [AccountSummary], transitions: [BandRecorder.Transition],
                                settings: AlertSettings, now: Date) -> [(AccountSummary, AlertNotice.Kind)] {
    var result: [(AccountSummary, AlertNotice.Kind)] = []
    for summary in summaries {
      if let until = settings.snoozedUntil[summary.provider], until > now { continue }
      if let change = transitions.last(where: { $0.accountID == summary.id }), change.band == summary.band {
        if change.band == .critical, change.from != .critical, settings.notifyCritical { result.append((summary, .critical)) }
        if change.band == .low, change.from != .low, change.from != .critical, settings.notifyLow {
          result.append((summary, .low))
        }
      }
      if settings.notifyUnknown, summary.band == .unknown, summary.needsAnchor,
         let since = summary.bandSince, now.timeIntervalSince(since) > unknownAfter {
        result.append((summary, .unknown))
      }
      if settings.notifyStale, summary.isStale, let last = summary.lastSuccessAt,
         now.timeIntervalSince(last) > staleAfter {
        result.append((summary, .stale))
      }
    }
    return result
  }

  /// Quiet hours in local time; `start > end` wraps past midnight (`23:00`–`07:00`). Equal ends mean none.
  public static func isQuiet(_ now: Date, settings: AlertSettings, calendar: Calendar) -> Bool {
    guard settings.quietHoursEnabled, settings.quietStart != settings.quietEnd else { return false }
    let parts = calendar.dateComponents([.hour, .minute], from: now)
    let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    if settings.quietStart < settings.quietEnd { return minute >= settings.quietStart && minute < settings.quietEnd }
    return minute >= settings.quietStart || minute < settings.quietEnd
  }

  /// 08's body: `OpenAI: ~1 d of runway left (≈ $9 ± 2).`; the other kinds' copy is authored (Q-043).
  public static func notice(_ summary: AccountSummary, kind: AlertNotice.Kind, hideCents: Bool) -> AlertNotice {
    let body: String
    switch kind {
    case .critical where summary.providerUnavailable:
      body = CoreStrings.Alerts.unavailable(summary.label)
    case .low, .critical:
      let runway = Formatters.runway(summary.runwayMin) ?? Formatters.runway(0) ?? ""
      let amount = summary.remainingCents.map { cents -> String in
        let money = Money(cents: cents, currency: summary.currency)
        if summary.mode == .anchored, let band = summary.estimateBandCents {
          return Formatters.estimate(money, bandCents: band, hideCents: hideCents, locale: .current)
        }
        return Formatters.remaining(money, hideCents: hideCents, locale: .current)
      }
      body = CoreStrings.Alerts.runwayLeft(summary.label, runway: runway, amount: amount)
    case .unknown: body = CoreStrings.Alerts.setAnchor(summary.label)
    case .stale: body = CoreStrings.Alerts.stale(summary.label)
    case .test: body = CoreStrings.Alerts.test
    }
    return AlertNotice(accountID: summary.id, provider: summary.provider, kind: kind, title: CoreStrings.Alerts.title,
                       body: body)
  }
}

/// Sends what `AlertPolicy` picks (14 § Stage 5.4): asks for authorization at the first alert (denied →
/// `ui.notification_denied`, once), holds notices during quiet hours and sends them when they end, and logs
/// `ui.notification_sent {acct, band, suppressed_by_quiet_hours}` per notice sent.
public actor AlertCenter {
  let notifier: any Notifier
  let log: EventLog
  private var lastSent: [String: Date] = [:]
  private var queue: [AlertNotice] = []
  private var authorized: Bool?

  public init(notifier: any Notifier, logPipeline: LogPipeline? = nil) {
    self.notifier = notifier
    log = EventLog(pipeline: logPipeline)
  }

  /// False after the user denied notifications (the Alerts tab's banner, O-11); nil before the first ask.
  public var isAuthorized: Bool? { authorized }

  /// Called after each evaluation with the band changes it logged.
  public func process(_ summaries: [AccountSummary], transitions: [BandRecorder.Transition], settings: AlertSettings,
                      now: Date, calendar: Calendar = .current) async {
    let quiet = AlertPolicy.isQuiet(now, settings: settings, calendar: calendar)
    if !quiet, !queue.isEmpty {
      let held = queue
      queue = []
      for notice in held { await send(notice, held: true) }
    }
    for (summary, kind) in AlertPolicy.candidates(summaries, transitions: transitions, settings: settings, now: now) {
      let key = "\(summary.id) \(kind.rawValue)"
      if let last = lastSent[key], now.timeIntervalSince(last) < AlertPolicy.dedupeWindow { continue }
      lastSent[key] = now
      let notice = AlertPolicy.notice(summary, kind: kind, hideCents: settings.hideCents)
      if quiet {
        queue.append(notice)
      } else {
        await send(notice, held: false)
      }
    }
  }

  /// `Send test notification`: true when it was handed to the system.
  public func sendTest(_ summary: AccountSummary?) async -> Bool {
    let notice = AlertNotice(accountID: summary?.id ?? "", provider: summary?.provider ?? .openai, kind: .test,
                             title: CoreStrings.Alerts.title, body: CoreStrings.Alerts.test)
    return await send(notice, held: false)
  }

  @discardableResult
  private func send(_ notice: AlertNotice, held: Bool) async -> Bool {
    if authorized == nil {
      authorized = await notifier.authorize()
      if authorized == false {
        log.emit(.warn, .uiNotificationDenied, cat: .ui, msg: "notifications are off in System Settings")
      }
    }
    guard authorized == true else { return false }
    do {
      try await notifier.deliver(notice)
    } catch {
      log.emit(.error, .uiError, cat: .ui, msg: "notification not delivered", acct: notice.provider.rawValue, err: error,
               ctx: ["view": "notification"])
      return false
    }
    log.emit(.info, .uiNotificationSent, cat: .ui, msg: "notification sent", acct: notice.provider.rawValue, ctx: [
      "band": .string(notice.kind.rawValue), "suppressed_by_quiet_hours": .bool(held)
    ])
    return true
  }
}
