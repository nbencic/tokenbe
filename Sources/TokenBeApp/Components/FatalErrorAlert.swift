import AppKit
import TokenBeCore

/// The alerts of launch step 2 (03 § Migrations, § Durability; 04 § Startup sequence).
@MainActor
enum FatalErrorAlert {
  /// The database could not be opened or migrated: names the migration, the error and the backup path, then the
  /// caller quits. Nothing has been deleted.
  static func show(_ failure: DatabaseOpenError) {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = Strings.databaseFatalTitle
    alert.informativeText = Strings.databaseFatalBody(
      migration: failure.migration, error: failure.message, database: failure.databasePath,
      backup: failure.backupPath
    )
    alert.addButton(withTitle: Strings.quit)
    NSApp.activate()
    alert.runModal()
  }

  /// A corrupt database was moved aside and replaced (by the backup, or a fresh one): both paths are shown.
  static func showRecovered(_ recovery: DatabaseRecovery) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = Strings.databaseRecoveredTitle
    alert.informativeText = Strings.databaseRecoveredBody(
      corruptCopy: recovery.corruptCopy.path, restoredFrom: recovery.restoredFrom?.path
    )
    alert.addButton(withTitle: Strings.okButton)
    NSApp.activate()
    alert.runModal()
  }
}
