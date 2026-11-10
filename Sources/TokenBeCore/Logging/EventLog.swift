import Foundation
import Synchronization

/// Logs through the given pipeline (tests, PM-2.1-2) or the process-wide `Log` (app). For Core types that log under
/// several categories (adapters, the poller); the store keeps its own `StoreLog`.
public struct EventLog: Sendable {
  public let pipeline: LogPipeline?

  public init(pipeline: LogPipeline? = nil) {
    self.pipeline = pipeline
  }

  /// The redactor whose exact pass sees the secrets in flight: the pipeline's in tests, `Log.redactor` in the app.
  public var redactor: Redactor { pipeline?.redactor ?? Log.redactor }

  // swiftlint:disable:next function_parameter_count
  public func emit(
    _ lvl: LogLevel, _ evt: Evt, cat: Cat, msg: String, acct: String? = nil, job: String? = nil,
    attempt: Int? = nil, err: (any Error)? = nil, dur: Duration? = nil, ctx: [String: LogValue] = [:]
  ) {
    if let pipeline {
      pipeline.emit(lvl, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
      return
    }
    switch lvl {
    case .debug: Log.debug(evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
    case .info: Log.info(evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
    case .notice:
      Log.notice(evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
    case .warn: Log.warn(evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
    case .error: Log.error(evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
    case .fault: Log.fault(evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
    }
  }
}

/// "Once per day" for 07's throttled events (`poll.unknown_keys`, `normalize.unknown_keys`): `first(key, on:)` is
/// true the first time `key` is seen on a UTC day. Only the current day is kept, so memory stays bounded.
public final class DailyOnce: Sendable {
  private struct State {
    var day = ""
    var seen: Set<String> = []
  }

  private let state = Mutex(State())

  public init() {}

  public func first(_ key: String, on date: Date) -> Bool {
    let day = Self.utcDay(date)
    return state.withLock { current in
      if current.day != day {
        current.day = day
        current.seen = []
      }
      return current.seen.insert(key).inserted
    }
  }

  /// `YYYY-MM-DD` of `date` in UTC, the day format of `cost_bucket.day` (03).
  public static func utcDay(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
