import Foundation
import Observation
import TokenBeCore

/// 04 § Daily activity in the app (14 § Stage 4.3 step 1, startup step 7). It registers
/// `NSBackgroundActivityScheduler` (`dev.bathyon.tokenbe.daily`, interval 86400 s, tolerance 3600 s, `.utility`,
/// repeating) over Core's `DailyActivity`, with the steps of 04 that exist so far, in 04's order:
/// `cost polls` → `price refresh` (5.1) → `db backup` → `weekly integrity_check` (every 7th run) →
/// `incremental_vacuum`. Roll-ups (9.1, between cost polls and the price refresh) and the update check (9.4, after
/// the price refresh) register at their 04 positions in their stages.
/// `Run daily tasks now` (Settings → Sources) runs the same function out of band. After each run it writes
/// `tb.daily.lastRunAt` and `tb.daily.runCount` (09); the backup and the integrity check write `tb.db.last*`.
@MainActor @Observable
final class DailyActivityRegistration {
  static let identifier = "dev.bathyon.tokenbe.daily"
  static let interval: TimeInterval = 86_400
  static let tolerance: TimeInterval = 3_600
  /// 04: the full `integrity_check` every 7th run.
  static let integrityEvery = 7

  /// True while a run is in progress; `Run daily tasks now` is disabled meanwhile.
  private(set) var isRunning = false
  @ObservationIgnored private let activity: DailyActivity
  @ObservationIgnored private let settings: TokenBeCore.Settings
  @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?

  /// A `weekly integrity_check` whose result is not `ok`: the step fails and is retried at the next activity. The
  /// check itself has logged `db.integrity_failed` and copied the database (03 § Durability).
  struct IntegrityFailed: Error, CustomStringConvertible {
    let result: String
    var description: String { "integrity_check: \(result)" }
  }

  init(settings: TokenBeCore.Settings, repository: any Repository, poller: Poller, prices: PriceBookModel?) {
    self.settings = settings
    let costPolls = CostPolls(store: repository, poller: poller, isPaused: {
      await MainActor.run { ScheduleSettings(settings).isPaused(at: Date()) }
    })
    activity = DailyActivity(steps: [
      DailyStep("cost polls") { _ in try await costPolls.run() },
      // A feed failure is logged by the fetcher and keeps the snapshot; only a store failure fails the step.
      DailyStep("price refresh") { _ in try await prices?.refresh() },
      DailyStep("db backup") { _ in
        _ = try await repository.backup()
        await MainActor.run { settings.dbLastBackupAt = Date().timeIntervalSince1970 }
      },
      DailyStep("weekly integrity_check", gate: .everyNthRun(Self.integrityEvery)) { _ in
        let result = try await repository.integrityCheck()
        await MainActor.run { settings.dbLastIntegrityCheckAt = Date().timeIntervalSince1970 }
        guard result.isOK else { throw IntegrityFailed(result: result.result) }
      },
      DailyStep("incremental_vacuum") { _ in _ = try await repository.incrementalVacuum() }
    ])
  }

  /// Startup step 7 (04): the system runs the activity about once a day, at a time it chooses (D-daily-no-fixed-time).
  func register() {
    let scheduler = NSBackgroundActivityScheduler(identifier: Self.identifier)
    scheduler.interval = Self.interval
    scheduler.tolerance = Self.tolerance
    scheduler.qualityOfService = .utility
    scheduler.repeats = true
    scheduler.schedule { [weak self] completion in
      Task { @MainActor in
        await self?.run()
        completion(.finished)
      }
    }
    self.scheduler = scheduler
  }

  /// App terminate.
  func invalidate() {
    scheduler?.invalidate()
    scheduler = nil
  }

  /// One run: the next run number (`tb.daily.runCount` + 1), then 09's bookkeeping. A request while a run is in
  /// progress is skipped by Core (`sched.overlap_skipped`) and writes nothing.
  func run() async {
    let runNumber = settings.dailyRunCount + 1
    isRunning = true
    let summary = await activity.run(runNumber: runNumber)
    isRunning = false
    guard summary != nil else { return }
    settings.dailyLastRunAt = Date().timeIntervalSince1970
    settings.dailyRunCount = runNumber
  }
}
