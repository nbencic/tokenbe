# Stage 2.2 — Observation plumbing & maintenance buttons (14 § Stage 2.2). Sourced by scripts/verify-stage.sh.

inventory=(
  Sources/TokenBeCore/Store/Observation.swift Sources/TokenBeCore/Ledger/AccountSummaryBuilder.swift
  Sources/TokenBeApp/SettingsUI/AdvancedTab.swift Tests/TokenBeCoreTests/ObservationTests.swift
  Tests/TokenBeUITests/AdvancedMaintenanceUITests.swift scripts/stages/2.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 1: the UI reads the database through ValueObservation (04 I2), mapped in Core (04 I3).
check "Repository includes ObservationRepository (PM-2.1-3)" grep -qF '& ObservationRepository' Sources/TokenBeCore/Store/Repository.swift
check "observation uses GRDB ValueObservation" grep -qF 'ValueObservation.tracking(' Sources/TokenBeCore/Store/Observation.swift
check "AppModel subscribes to observeSummaryInputs" grep -qF 'repository.observeSummaryInputs()' Sources/TokenBeApp/AppModel.swift
check "AppModel maps through AccountSummaryBuilder" grep -qF 'AccountSummaryBuilder.summaries(' Sources/TokenBeApp/AppModel.swift
check "AppDelegate starts the observation from AppEnvironment.repository" grep -qF 'model.observe(repository)' Sources/TokenBeApp/AppDelegate.swift
check "TokenBeApp never imports GRDB (04)" bash -c "! grep -rqE '^import GRDB' Sources/TokenBeApp"

# Step 2: 08's two rows, in 08's order, each writing its 09 key.
for copy in "Run integrity check now" "Back up now"; do
  check "Strings has copy: $copy" grep -qF "\"$copy\"" Sources/TokenBeApp/Strings.swift
done
row_order() {
  local integrity backup
  integrity="$(grep -n 'Strings.runIntegrityCheckNow' Sources/TokenBeApp/SettingsUI/AdvancedTab.swift | head -n 1 | cut -d: -f1)"
  backup="$(grep -n 'Strings.backUpNow' Sources/TokenBeApp/SettingsUI/AdvancedTab.swift | head -n 1 | cut -d: -f1)"
  [[ -n "$integrity" && -n "$backup" && "$integrity" -lt "$backup" ]] || { echo "integrity row $integrity, backup row $backup"; return 1; }
}
check "Advanced rows in 08 order: integrity check, then backup" row_order
check "integrity check sets tb.db.lastIntegrityCheckAt" grep -qF 'settings.dbLastIntegrityCheckAt = ' Sources/TokenBeApp/SettingsUI/AdvancedTab.swift
check "backup sets tb.db.lastBackupAt" grep -qF 'settings.dbLastBackupAt = ' Sources/TokenBeApp/SettingsUI/AdvancedTab.swift
check "button failures log ui.error" test "$(grep -c '\.uiError' Sources/TokenBeApp/SettingsUI/AdvancedTab.swift)" -eq 2
check "no confirm dialog on the maintenance rows (08 lists one only for Reset, Q-025)" bash -c "! grep -qE 'confirmationDialog|\\.alert\\(' Sources/TokenBeApp/SettingsUI/AdvancedTab.swift"
check "check-log-events.sh" scripts/check-log-events.sh

for suite in ObservationTests AccountSummaryBuilderTests RepositoryAccountTests SettingsTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "AdvancedMaintenanceUITests passed" grep -q "Test Suite 'AdvancedMaintenanceUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"

# 14 Verify, under the UI test's TOKENBE_TEST_ROOT (Q-025): the test itself asserts tokenbe.sqlite.bak in its root;
# here, both 09 keys were written by the last UI-test run, and the owner's real support folder has no new file.
written_by_last_uitest() {
  local value started
  value="$(defaults read dev.bathyon.tokenbe.uitests "$1" 2>/dev/null | cut -d. -f1)"
  started="$(cat build/run/uitest.start 2>/dev/null)"
  [[ -n "$value" && -n "$started" && "$value" -ge "$started" ]] || { echo "$1 = '$value', last uitest started $started"; return 1; }
}
check "UI-test suite: tb.db.lastBackupAt set by the last UI-test run" written_by_last_uitest tb.db.lastBackupAt
check "UI-test suite: tb.db.lastIntegrityCheckAt set by the last UI-test run" written_by_last_uitest tb.db.lastIntegrityCheckAt
check "owner's real support folder untouched (no tokenbe.sqlite.bak there)" real_support_unchanged
check "owner's real TokenBe settings (tb.*) unchanged" real_tb_unchanged
