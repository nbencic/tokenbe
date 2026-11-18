# Postmortem — Stage 9.3 Diagnostics bundle
Date: 2026-11-18 · Branch: s9.3-diagnostics · PR: #41 · Planned size: S · Commits: 7

## Outcome
Settings → Advanced → `Export diagnostics…` sits between `Log retention` and `Open log folder` (08). It saves 07's zip, `TokenBe-diagnostics-YYYYMMDD-HHMMSS.zip` (UTC):
- the newest 3 NDJSON logs, as written;
- `breadcrumbs.ndjson`;
- `settings.json` (every `tb.*` key);
- `schema.sql`;
- `db-stats.json`;
- `poll_state.json` (`last_raw` as text, redacted again);
- `price-overrides.json`;
- `environment.json`.

The files are zipped with `ditto -c -k --sequesterRsrc` (D-ditto-zip). The bundle never reads the database file or the Keychain, and it logs `app.diagnostics_exported {path, bytes, files}`. D1–D13 are met. No H-gate belongs to this stage; H2 and H3 stay open (owner).

## What went as planned
- **The advisor's review settled five points before any code:**
  - a `ditto` probe, which found no `__MACOSX` entries for plain files;
  - no `try?` in the cleanup;
  - drain the log pipeline first, so the newest log holds the click's records;
  - confirm breadcrumbs are sanitized before they enter the ring (they are, `Log.remember` after `makeRecord`);
  - reuse NDJSONSink's file-name rule, so rotation `-10` sorts after `-2` and crash files never count.
- **Each test passed on its first run:**
  - `DiagnosticsBundleTests` (5 cases), with the LogSink suite: 25 tests in 3 suites;
  - AdvancedMaintenanceUITests (`testExportDiagnostics`, with the two earlier tests: 3 tests in 1 min 26 s).
- **Planted key.** The SEC-1 case writes a key-shaped string straight into `poll_state.last_raw`, bypassing the adapter's redaction. The bundle shows the marker, and no file in it matches a key pattern.
- **PM-8.3-1 held** (grep first). 1.3.sh's last export guard is retired. 9.2.sh's check that pinned 1.3.sh's exact guard line is now a pattern (`no Export/Import guard`), so later stages can change that line without breaking it.

## What went wrong
1. **`Mutex` as an optional parameter did not compile.**
   - **Symptom:** the first test build failed: "parameter of noncopyable type 'Mutex<Bool>?' must specify ownership".
   - **Fix:** a small `Sendable` class holds the flag.
   - **Cost:** one build.
2. **The coverage gate fell to 96.89 %.**
   - **Symptom:** CI (63e7559) and full verify 1 failed 0.5's gate: Core lines 96.89 % / 96.94 % < 97 % (Q-035). `DiagnosticsBundle.swift` was at 82 %.
   - **Root cause:** the tests covered the paths that succeed, but not the failure paths (a tool that can't start, a move that fails and the staging cleanup after it) or the non-text and null branches. Core was already near the floor (97.0x %), so about 30 untested lines in a new file were enough to sink it.
   - **Fix:** `DiagnosticsBundleTests.failures` and `values`. To keep the cleanup assertion free of races with parallel tests, `export` takes an internal `scratch` folder, and the test owns that folder. The gate now reads 97.11 %.
   - **Cost:** one CI run and one full verify.
   - **Lesson:** run `scripts/coverage-gate.sh 97` after `swift test --enable-code-coverage` before the first full verify of a stage that adds a Core file. A new file with untested error paths can sink the gate from 97.1 %.
3. **An earlier stage's glob check matched a new file.**
   - **Symptom:** full verify 2 failed 9.2's negative grep over `Export/*.swift` (above).
   - **Root cause:** a guard written over a folder glob also guards files that later stages add to that folder. PM-8.3-2's sweep grepped for names (`Export`, `Import`), not for globs over the folders this stage writes into.
   - **Fix:** the check lists its own files.
   - **Cost:** one full verify (about 20 min).
   - **Lesson:** before the first full verify, also grep `scripts/stages/*.sh` for globs over each folder the stage adds a file to (`<folder>/*.swift`), and dry-run every check of the stages whose files changed, not only the edited lines.
4. **One shell command was refused by the harness's safety check.**
   - **Symptom:** an `rm -f $D/*.dry.sh` cleanup with an unguarded variable was refused. The whole command didn't run, including writing 9.3.sh. Later a `bash -c` script containing `rm` was refused too.
   - **Fix:** the script was written with the editor, and dry-run files stay in the session scratchpad without cleanup.
   - **Cost:** two retries, no lost work.

## Verify and CI failures
- **Core and lint:** 25 tests in the touched suites passed (after What went wrong 1). Lint was clean on the first run. One extra run: the first cleanup assertion raced parallel tests over the shared temp folder, fixed by the `scratch` parameter.
- **Stage-script dry run** (9.3's static checks and 9.2's rewritten 1.3 check): every check passed.
- **UI, targeted:** AdvancedMaintenanceUITests passed, 3 tests in 1 min 26 s.
- **Full verify 1** (Q-047 selected 6 suites; no shared file changed): FAIL 0.5, the coverage gate (What went wrong 2). All 8 UI tests passed in 6 min 34 s, and 574 Core tests passed.
- **Full verify 2:** FAIL 9.2, `poll_state and ingest_file are not exported`. That check grepped `Export/*.swift`, and 9.3's `DiagnosticsBundle.swift` lives there and writes `poll_state.json` by design (07). **Fix:** the check names 9.2's three exporter files. The coverage gate passed (97.11 %), and the 8 UI tests passed again. My dry run had exercised only one line of 9.2.sh, so it missed this; the re-run dry-ran 9.1–9.3 in full (What went wrong 3).
- **Full verify 3:** `STAGE 9.3 OK`, with 1 479 checks passed and 23 printing `skip` (the unselected suites' checks and 3.6's H2 check). 8 UI tests passed with 0 failures in 6 min 34 s; 576 Core tests in 86 suites passed; coverage 97.11 %.
- **CI:** red on 63e7559 (the coverage gate, What went wrong 2), green from 44cd04d; the head that carries this file is checked by SHA before the merge.

## Deviations from the docs
- **07 § Diagnostics bundle** leaves the time zone of the file name open; it is UTC. Its `settings.json` covers the per-provider keys too (Q-057).
- **04 § Retry's decode badge** ("Provider changed its response · Copy diagnostics") is not built. 08 gives it no place and 14 no stage (Q-057, PM-9.3-1).
- **14 § Stage 9.3:** the Inventory now lists the files, and the Tests line the UI test.

## Judgment calls
- Q-057: the diagnostics bundle rules the docs leave open:
  - the UTC file name;
  - which logs, and the drain before copying;
  - each file's content;
  - the staging, `ditto` and cleanup;
  - the button's place and sheet;
  - the decode badge left for 11.3.

## Carry-forward actions
- PM-9.3-1 · agent · 11.3 · 04 § Retry's decode badge ("Provider changed its response · Copy diagnostics", after 3 decode failures in a row) has no place in 08 and no stage in 14. Decide where it sits on the account page and what "Copy diagnostics" copies (likely the failing job's redacted `last_raw` on the pasteboard), then build it or record why not.
- Earlier actions that targeted 9.3:
  - PM-8.3-1: closed for 9.3 (the `Export diagnostics` guard retired); still open for 9.4 (`Check for updates`) and 9.5 (`Reset all`). Status edited in stage-8.3 and phase-8.
- Still open:
  - PM-9.2-1 (11.2);
  - PM-9.1-1 (11.1);
  - PM-8.1-1 (the H2 PR);
  - PM-8.1-2 (10.1);
  - PM-8.1-3 (9.5);
  - PM-8.4-1 (owner, 11.3);
  - PM-8.4-2 (11.3);
  - PM-4.3-3 (9.4).
