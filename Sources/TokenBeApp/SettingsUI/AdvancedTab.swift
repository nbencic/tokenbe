import SwiftUI
import TokenBeCore

/// Advanced tab (08 § Settings, Paper `1WN-0`, `22Q-0`): log level (live, 07), log retention, `Open log folder`;
/// `Last daily run` (14 § Stage 4.3, 09 `tb.daily.lastRunAt`); `Run integrity check now` and `Back up now`
/// (14 § Stage 2.2). Diagnostics and data rows arrive in 9.x.
struct AdvancedTab: View {
  @Bindable var settings: TokenBeCore.Settings
  let logsDirectory: URL
  /// Nil only when startup step 2 failed, and then the app quits (03 § Migrations).
  let repository: (any Repository)?

  var body: some View {
    Form {
      Section {
        Picker(Strings.logLevel, selection: $settings.logLevel) {
          Text(Strings.logLevelDebug).tag("debug")
          Text(Strings.logLevelInfo).tag("info")
          Text(Strings.logLevelWarn).tag("warn")
          Text(Strings.logLevelError).tag("error")
        }
        .accessibilityIdentifier("settings.advanced.logLevel")
        Stepper(value: $settings.logRetentionDays, in: SettingsKey.logRetentionDays.spec.intBounds ?? 1...90) {
          LabeledContent(Strings.logRetention, value: Strings.days(settings.logRetentionDays))
        }
        .accessibilityIdentifier("settings.advanced.logRetention")
        OpenLogFolderButton(logsDirectory: logsDirectory)
          .accessibilityIdentifier("settings.advanced.openLogFolder")
      }
      if let repository {
        Section {
          LabeledContent(Strings.lastDailyRun, value: lastDailyRun)
            .accessibilityIdentifier("settings.advanced.lastDailyRun")
          DatabaseMaintenanceRows(settings: settings, repository: repository)
        }
      }
    }
    .formStyle(.grouped)
  }

  /// `never`, or the date and time of the last run (`Nov 12 21:30`, as the backup sheet writes it, Q-025).
  private var lastDailyRun: String {
    guard settings.dailyLastRunAt > 0 else { return Strings.never }
    return Strings.dateTime(Date(timeIntervalSince1970: settings.dailyLastRunAt))
  }
}

/// What a maintenance button reports in its sheet.
struct MaintenanceReport: Identifiable {
  let id = UUID()
  let title: String
  let lines: [String]
}

/// 14 § Stage 2.2 step 2, in 08's order. Each button runs its `Repository` call (which logs its `db.*` event),
/// records the time in its 09 key, and shows the outcome in a sheet.
struct DatabaseMaintenanceRows: View {
  let settings: TokenBeCore.Settings
  let repository: any Repository
  @State private var running = false
  @State private var report: MaintenanceReport?

  var body: some View {
    Button(Strings.runIntegrityCheckNow) { run(integrityCheck) }
      .disabled(running)
      .accessibilityIdentifier("settings.advanced.integrityCheck")
    Button(Strings.backUpNow) { run(backUp) }
      .disabled(running)
      .accessibilityIdentifier("settings.advanced.backUp")
      .sheet(item: $report) { report in
        MaintenanceReportSheet(report: report) { self.report = nil }
      }
  }

  private func run(_ action: @escaping @MainActor () async -> MaintenanceReport) {
    running = true
    Task {
      report = await action()
      running = false
    }
  }

  /// `db.integrity_check`; sets `tb.db.lastIntegrityCheckAt`; shows `ok` or the first error line and, on failure,
  /// where the copy of the database went (Q-024).
  private func integrityCheck() async -> MaintenanceReport {
    do {
      let result = try await repository.integrityCheck()
      settings.dbLastIntegrityCheckAt = Date().timeIntervalSince1970
      var lines = [Strings.integrityResult(result.result)]
      if let copy = result.corruptCopy { lines.append(Strings.corruptCopy(copy.path)) }
      return MaintenanceReport(title: Strings.integrityCheckTitle, lines: lines)
    } catch {
      Log.error(.uiError, cat: .ui, msg: "integrity check failed to run", err: error, ctx: [
        "view": "settings.advanced"
      ])
      return MaintenanceReport(title: Strings.integrityCheckFailedTitle, lines: [error.localizedDescription])
    }
  }

  /// `db.backup`; sets `tb.db.lastBackupAt`; shows the backup's size, time and path.
  private func backUp() async -> MaintenanceReport {
    do {
      let result = try await repository.backup()
      settings.dbLastBackupAt = Date().timeIntervalSince1970
      let size = Int64(result.bytes).formatted(.byteCount(style: .file))
      // 08 § Formatting rules fixes dates (`MMM d`); the time of day is added, since 08 has no rule for it (Q-025).
      let time = Strings.dateTime(Date(timeIntervalSince1970: settings.dbLastBackupAt))
      return MaintenanceReport(title: Strings.backupTitle,
                               lines: [Strings.backupDetail(size: size, time: time), result.url.path])
    } catch {
      Log.error(.uiError, cat: .ui, msg: "backup failed", err: error, ctx: ["view": "settings.advanced"])
      return MaintenanceReport(title: Strings.backupFailedTitle, lines: [error.localizedDescription])
    }
  }
}

struct MaintenanceReportSheet: View {
  let report: MaintenanceReport
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(report.title)
        .font(.headline)
        .accessibilityIdentifier("settings.advanced.report.title")
      ForEach(Array(report.lines.enumerated()), id: \.offset) { index, line in
        Text(line)
          .monospacedDigit()
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("settings.advanced.report.line\(index)")
      }
      HStack {
        Spacer()
        Button(Strings.okButton, action: dismiss)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("settings.advanced.report.ok")
      }
    }
    .padding(20)
    .frame(width: 420)
  }
}
