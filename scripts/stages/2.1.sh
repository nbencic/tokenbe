# Stage 2.1 — Database, migration 001, Repository (14 § Stage 2.1). Sourced by scripts/verify-stage.sh.

store=Sources/TokenBeCore/Store
inventory=(
  $store/Database.swift $store/Migrator.swift $store/Integrity.swift $store/Repository.swift $store/GRDBRepository.swift
  $store/Migrations/001_initial.sql Sources/TokenBeApp/Components/FatalErrorAlert.swift
  Tests/TokenBeCoreTests/Support/FixtureDBBuilder.swift Tests/TokenBeCoreTests/Support/MemoryRepository.swift
  Tests/Fixtures/db/schema_v1.sqlite Tests/Fixtures/db/corrupt.sqlite
  Tests/TokenBeCoreTests/MigrationTests.swift Tests/TokenBeCoreTests/RepositoryAccountTests.swift scripts/stages/2.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done
for record in Account ProviderKey App AppBinding UsageBucket CostBucket BalanceSnapshot HarnessEvent IngestFile \
              LedgerEvent PriceSnapshot PriceOverride PollState BandState; do
  check "record type ${record}Record" grep -q "public struct ${record}Record: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord" "$store/Records/${record}Record.swift"
done
check "exactly 14 record files" test "$(ls $store/Records/*.swift | wc -l | tr -d ' ')" -eq 14

# 001 is 03's DDL verbatim (03 is authoritative), plus the two seed rows.
ddl_03() { awk '/^## Schema \(migration 001/ {s = 1} s && /^```sql/ {i = 1; next} i && /^```/ {exit} i' docs/03-data-model.md; }
ddl_001() { sed -n '/^CREATE TABLE schema_version/,/^-- Seed rows/p' $store/Migrations/001_initial.sql | sed '$d' | sed '$d'; }
ddl_matches() { diff <(ddl_03) <(ddl_001); }
check "001_initial.sql contains 03's DDL verbatim" ddl_matches
check "001 creates the 15 tables of 03" test "$(grep -c '^CREATE TABLE' $store/Migrations/001_initial.sql)" -eq 15
check "001 seeds schema_version(1)" grep -qE "^INSERT INTO schema_version \(version, applied_at\) VALUES \(1, " $store/Migrations/001_initial.sql
check "001 seeds app('app_unassigned')" grep -qF "VALUES ('app_unassigned', 'unassigned', 'Unassigned'," $store/Migrations/001_initial.sql
check "corrupt.sqlite is the first 4 KiB of schema_v1.sqlite" cmp Tests/Fixtures/db/corrupt.sqlite <(head -c 4096 Tests/Fixtures/db/schema_v1.sqlite)
check "schema_v1.sqlite is a single file (no WAL mode)" test "$(sqlite3 -readonly Tests/Fixtures/db/schema_v1.sqlite 'PRAGMA journal_mode')" = delete
check "schema_v1.sqlite passes integrity_check" test "$(sqlite3 -readonly Tests/Fixtures/db/schema_v1.sqlite 'PRAGMA integrity_check')" = ok

# 04: the app never imports GRDB; no stubs for later aggregates (14 step 5).
check "TokenBeApp never imports GRDB (04)" bash -c "! grep -rqE '^import GRDB' Sources/TokenBeApp"
check "no stubs in Store" bash -c "! grep -rqE 'fatalError|notImplemented|not implemented' $store"
# 2.2 adds ObservationRepository (14 § Stage 2.2 step 1); 3.4 adds providerKeys/usage/cost/poll on the next line
# (3.4.sh checks it); later aggregates join with their stages.
check "Repository declares only the aggregates built so far" grep -qx 'public typealias Repository = AccountRepository & MaintenanceRepository & ObservationRepository' $store/Repository.swift
for evt in dbOpen dbMigrate dbMigrateFailed dbQuickCheck dbIntegrityCheck dbIntegrityFailed dbCorrupt dbRestore dbBackup \
           dbBackupFailed dbVacuum dbBusy; do
  check "event .$evt emitted by Store" grep -rqF ".$evt" $store
done
check "check-log-events.sh" scripts/check-log-events.sh
declared_steps() { grep -oE 'StartupStep\("[a-z ]+"\)' Sources/TokenBeApp/Startup.swift | cut -d'"' -f2 | paste -sd, -; }
check "startup step 2 is the database (04), then the login item" test "$(declared_steps)" = "logging,database,login item"
check "fatal alert on database failure, then terminate" grep -qF 'FatalErrorAlert.show(databaseFailure)' Sources/TokenBeApp/Startup.swift

for suite in MigrationTests DurabilityTests FixtureDBTests RepositoryAccountTests RecordRoundTripTests StartupSequenceTests; do
  check "suite $suite passed" suite_passed "$suite"
done

# 14 Verify: launch the Debug app on a throwaway TOKENBE_TEST_ROOT (Q-014). While it runs, tokenbe.sqlite and its WAL
# exist; the log has db.open and db.migrate from=0 to=1, startup steps in 04 order, and no error or fault.
APP="build/DerivedData/Build/Products/Debug/TokenBe.app"
db_root="$(mktemp -d)/tokenbe-verify-2.1"
db_dir="$db_root/Application Support/TokenBe"
db_log() { cat "$db_root"/Logs/TokenBe/tokenbe-*.ndjson 2>/dev/null; }
launch_and_inspect() { # launch_and_inspect <launches so far, this one included>; db.migrate ran on the first only
  local i
  open -n --env "TOKENBE_TEST_ROOT=$db_root" "$APP" || return 1
  for i in $(seq 1 60); do [[ "$(db_log | grep -c '"startup_step":"login item"')" -ge "$1" ]] && break; sleep 0.5; done
  [[ -s "$db_dir/tokenbe.sqlite" ]] || { echo "no tokenbe.sqlite"; return 1; }
  [[ -e "$db_dir/tokenbe.sqlite-wal" ]] || { echo "no tokenbe.sqlite-wal while running"; return 1; }
  [[ "$(stat -f %Lp "$db_dir")" == 700 ]] || { echo "support folder is $(stat -f %Lp "$db_dir"), want 700"; return 1; }
  osascript -e 'quit app "TokenBe"' >/dev/null
  for i in $(seq 1 40); do pgrep -f "$APP/Contents/MacOS/TokenBe" >/dev/null || break; sleep 0.5; done
  ! pgrep -f "$APP/Contents/MacOS/TokenBe" >/dev/null || { echo "TokenBe did not exit"; return 1; }
  [[ "$(db_log | grep -c '"evt":"db.migrate"')" -eq 1 ]] || { echo "db.migrate logged $(db_log | grep -c '"evt":"db.migrate"') times, want 1"; return 1; }
}
logged_open() { db_log | grep '"evt":"db.open"' | grep -q '"journal_mode":"wal"'; }
logged_migrate() { db_log | grep '"evt":"db.migrate"' | grep -q '"from":0,"to":1'; }
logged_quick_check() { db_log | grep '"evt":"db.quick_check"' | grep -q '"result":"ok"'; }
steps_in_order() {
  local steps; steps="$(db_log | grep -oE '"startup_step":"[a-z ]+"' | head -n 3 | cut -d'"' -f4 | paste -sd, -)"
  [[ "$steps" == "logging,database,login item" ]] || { echo "first launch's steps: $steps"; return 1; }
}
no_db_errors() { ! db_log | grep -E '"lvl":"(error|fault)"'; }

check "launch: tokenbe.sqlite + WAL exist, folder 0700" launch_and_inspect 1
check "log has db.open (journal_mode wal)" logged_open
check "log has db.migrate from=0 to=1" logged_migrate
check "log has db.quick_check ok" logged_quick_check
check "startup steps logged in 04 order" steps_in_order
check "relaunch on the same data: no second migration" launch_and_inspect 2
check "zero error/fault records across both launches (D10)" no_db_errors
check "owner's real support folder untouched" real_support_unchanged
