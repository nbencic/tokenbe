# Stage 7.2 — Harness ingest (14 § Stage 7.2). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
ing=$core/Ingest
fx=Tests/Fixtures/harness
inventory=(
  $ing/FileWatcher.swift $ing/FSEventsWatcher.swift $ing/LineParser.swift $ing/Tailer.swift $ing/IngestService.swift
  $ing/IngestService+Read.swift $ing/IngestService+Files.swift $core/Normalize/HarnessNormalizer.swift
  $core/Store/Repository+Ingest.swift $core/Ledger/Attribution+Harness.swift
  $app/SettingsUI/HarnessReportsSection.swift $app/Resources/reporters/tokenbe_report.py
  $app/Resources/reporters/tokenbe_report.js
  $fx/valid_500.jsonl $fx/partial_write.jsonl $fx/bad_version.jsonl $fx/bad_json.jsonl $fx/unknown_provider.jsonl
  $fx/too_long_line.jsonl $fx/future_ts.jsonl $fx/openrouter_cost_cents.jsonl
  Tests/TokenBeCoreTests/LineParserTests.swift Tests/TokenBeCoreTests/IngestTailerTests.swift
  Tests/TokenBeCoreTests/AttributionHarnessTests.swift
  Tests/TokenBeUITests/HarnessIngestUITests.swift Tests/TokenBeUITests/HarnessRejectedUITests.swift
  scripts/stages/7.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 11's fixture: 500 lines, 488 distinct request ids, 3 apps, 2 providers.
fixture_counts() {
  python3 -I - "$fx/valid_500.jsonl" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1])]
ok = (len(lines) == 500 and len({l["request_id"] for l in lines}) == 488 and len({l["app"] for l in lines}) == 3
      and len({l["provider"] for l in lines}) == 2)
sys.exit(0 if ok else 1)
PY
}
check "valid_500.jsonl: 500 lines, 12 duplicates, 3 apps, 2 providers (11)" fixture_counts
check "harness fixtures are redacted (R11)" scripts/record-fixtures.sh --verify-redacted "$fx"

# Step 1: startup step 5, after prices (04), in the database's support folder (never the owner's in tests, D10).
check "startup step 5 (ingest) follows prices (04)" bash -c "grep -A1 'StartupStep(\"prices\")' $app/Startup.swift | grep -qF 'StartupStep(\"ingest\")'"
check "the ingest folder is the data root's, not tb.ingest.folderPath" grep -qF 'folder: paths.support.appendingPathComponent("ingest", isDirectory: true)' $app/Startup.swift
check "ingest/, ingested/, rejected/ are created (06)" bash -c "grep -qF 'for url in [folder, ingestedFolder, rejectedFolder]' $ing/IngestService.swift"
# Step 2: FSEvents per 06 (latency 1.0, three flags), the 30 s poll as fallback, no app logic on a queue (R6).
check "FSEvents flags FileEvents | UseCFTypes | NoDefer, latency 1.0 (06)" bash -c "grep -qF 'kFSEventStreamCreateFlagNoDefer' $ing/FSEventsWatcher.swift && grep -qF 'latency: TimeInterval = 1.0' $ing/FSEventsWatcher.swift"
check "the poll fallback is 30 s (06)" grep -qF 'interval: Duration = .seconds(30)' $ing/FileWatcher.swift
check "DispatchQueue only to deliver FSEvents (R6, Q-049)" bash -c "[[ \$(grep -rn 'DispatchQueue' $ing | grep -v '^[^:]*:[0-9]*: *///' | wc -l) -eq 1 ]] && grep -qF 'FSEventStreamSetDispatchQueue(ref, DispatchQueue.main)' $ing/FSEventsWatcher.swift"
# Step 3: 64 KiB chunks and lines, 1 000-line transactions, 2 s quiescence, the exclusive-lock heuristic.
check "64 KiB chunks and line limit, 1 000-line batches, 10 000-line burst (06)" bash -c "grep -qF 'chunkBytes = 64 * 1024' $ing/Tailer.swift && grep -qF 'maxLineBytes = 64 * 1024' $ing/LineParser.swift && grep -qF 'batchLines = 1_000' $ing/IngestService.swift && grep -qF 'burstLines = 10_000' $ing/IngestService.swift"
check "quiescence 2 s; O_WRONLY | O_EXLOCK | O_NONBLOCK before a move (06 § Tailing 5)" bash -c "grep -qF 'quiescence: Duration = .seconds(2)' $ing/IngestService.swift && grep -qF 'O_WRONLY | O_EXLOCK | O_NONBLOCK' $ing/IngestService+Files.swift"
check "applyIngestBatch writes events, buckets and the file row in one transaction (V7)" bash -c "grep -A14 'public func applyIngestBatch' $core/Store/Repository+Ingest.swift | grep -qF 'try Self.saveFile(batch'"
# Step 4: dedup by INSERT OR IGNORE; harness_tag binding; the key hint's last 4.
check "processLine: INSERT OR IGNORE, harness_tag binding, key hint by redacted's last 4 (06)" bash -c "grep -qF 'INSERT OR IGNORE INTO harness_event' $core/Store/Repository+Ingest.swift && grep -qF \"'harness_tag'\" $core/Store/Repository+Ingest.swift && grep -qF 'substr(redacted, -4) = ?' $core/Store/Repository+Ingest.swift"
# Step 5: attribution kinds; harness spend only in USD (Q-049).
check "the badges ≈ split, harness, inferred (08)" bash -c "grep -qF 'case key, split, harness, inferred' $core/Ledger/Attribution.swift && grep -qF '\"\\u{2248} split\"' $app/Strings.swift"
check "harness spend counts only for USD accounts without a usage API (05, R13)" grep -qF 'source == "harness" ? !usageAPI && currency == .usd : true' $core/Ledger/Spend.swift
check "the daily activity logs ledger.harness_drift" bash -c "grep -qF 'DailyStep(\"harness drift\")' $app/DailyActivityRegistration.swift && grep -qF '.ledgerHarnessDrift' $core/Ledger/Attribution+Harness.swift"
# Step 6: the Sources group and the bundled snippets, byte-identical to docs/reporters and in the README.
check "the bundled reporters are docs/reporters byte for byte" bash -c "cmp -s docs/reporters/tokenbe_report.py $app/Resources/reporters/tokenbe_report.py && cmp -s docs/reporters/tokenbe_report.js $app/Resources/reporters/tokenbe_report.js"
readme_has_snippets() {
  python3 -I - <<'PY'
import sys
readme = open("README.md").read()
sys.exit(0 if all(open(f"docs/reporters/tokenbe_report.{e}").read().rstrip("\n") in readme for e in ("py", "js")) else 1)
PY
}
check "the README carries both snippets verbatim (06)" readme_has_snippets
check "08's copy: Watching · N files · last line, Report apps from your harness →, Harness · … lines today" bash -c "grep -qF '\"Watching \\u{00B7} ' $app/Strings.swift && grep -qF 'Report apps from your harness \\u{2192}' $app/Strings.swift && grep -qF 'lines today' $app/Strings.swift"
check "Sources → Harness reports binds tb.ingest.enabled and tb.ingest.moveWhenDone (09)" bash -c "grep -qF '\$settings.ingestEnabled' $app/SettingsUI/HarnessReportsSection.swift && grep -qF '\$settings.ingestMoveWhenDone' $app/SettingsUI/HarnessReportsSection.swift"
check "the settings reach the service live (09, D4)" bash -c "grep -qF 'IngestSettings.keys.contains(key)' $app/Startup.swift"

for suite in LineParserTests IngestTailerTests AttributionTests ObservationTests StartupSequenceTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
check "the bundled reporters are in the app (Resources)" bash -c "test -s build/DerivedData/Build/Products/Debug/TokenBe.app/Contents/Resources/tokenbe_report.py && test -s build/DerivedData/Build/Products/Debug/TokenBe.app/Contents/Resources/tokenbe_report.js"
check "E2E-3 asserts A3's 5 s on the first burst" grep -qF 'A3: the first burst' Tests/TokenBeUITests/HarnessIngestUITests.swift
ui_check "HarnessIngestUITests passed (E2E-3, A3)" grep -q "Test Suite 'HarnessIngestUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
ui_check "HarnessRejectedUITests passed" grep -q "Test Suite 'HarnessRejectedUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
