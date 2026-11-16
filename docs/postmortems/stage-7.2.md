# Postmortem — Stage 7.2 Harness ingest
Date: 2026-11-15 · Branch: s7.2-harness-ingest · PR: #32 · Planned size: L · Commits: 14

## Outcome
A harness can now report its requests to TokenBe. It appends one v1 JSON line per request to a file in the drop folder, and TokenBe attributes the spend to the line's app within seconds.
- **Ingest (06):** FSEvents watches the folder, with a 30 s poll as fallback.
  - Each file is read from its stored offset; a partial last line waits for its `\n`.
  - Lines are applied in 1 000-line transactions together with the file's offset (V7), so a crash never double-counts.
  - Duplicates are ignored, and a conflicting duplicate is logged.
  - A file quiet for 2 s moves to `ingested/`. A file whose first line is not v1 JSON goes to `rejected/`.
- **Attribution:** every 06 path exists. An OpenAI key's day is split among the harness apps that used it (`≈ split`). A DeepSeek or xAI account takes its spend from harness lines (`harness`). A single-app DeepSeek account's balance drop on a day with no lines is attributed to that app (`inferred`). Drift against the balance is logged daily (`ledger.harness_drift`).
- **Burn and runway:** DeepSeek gets burn and runway from harness spend (PM-6.1-3), and an anchored xAI account gets spend from harness lines (PM-6.2-2). Both apply only to USD accounts.
- **UI:**
  - Settings → Sources → Harness reports shows the folder, the watch and move toggles, the status, today's counters and lines for providers not added, and copies a reporter snippet.
  - An empty By-app table links there.
  - The Sources strip has a harness column.
  - The README carries both reporters.

D1–D13 are met. Gates H2 and H3 are still open (owner) and do not block.

## What went as planned
- **The advisor's traps were designed out before any code:**
  - The folder comes from the data root, so the D10 checks pass and no test touched the owner's `ingest/`.
  - Harness spend counts only in USD (R13).
  - 03's column names were kept.
  - Buckets are priced from their summed classes, the way a reprice does.
  - Fixture `ts` values are moved to "now" in the UI test, and Core tests inject `now`.
- **A draft PR went up as soon as Core compiled** (PM-7.1-7), so CI's Xcode 16.4 saw the FSEvents and `Mutex` code early.
- **V7 is tested without a production hook.** A test-only SQLite trigger raises on the `ingest_file` write, and the events, buckets and apps of that batch roll back.
- **The 06 fixtures were generated once and checked by script:** 500 lines, 488 distinct ids, 3 apps, 2 providers. Both test price feeds price their models, so the spend assertions test real figures.
- **Coverage:** 97.18 % (gate 97 %) after targeted cases for the rarer failure branches.
- **Flake loop (PM-1.2-3):** 50 full Core runs, 0 failures.

## What went wrong
1. **The Mac's screen was locked for most of the stage** (`IOConsoleLocked = true`). The first UI run of the two new suites failed at the first popover click, so no new UI code was exercised. Per PM-1.1-1, everything else was finished first and the owner was asked to unlock.
   - Once unlocked, the two new suites ran first (1 min) before the full run. `HarnessRejectedUITests` passed. `HarnessIngestUITests` passed every ingest check (A3, 488 rows after the kill, the three By-app rows) but could not find the Sources strip's harness column.
   - **Cause:** the strip's `LazyVGrid` (7.1) builds only the rows on screen. On a 600 pt account page the third row (prices, harness) sat below the fold, so it was not in the accessibility tree.
   - **Fix:** the test scrolls the page first (d07aacc). Cost: one 1-minute run.
   - **Lesson:** a lazy container hides off-screen elements from UI tests; scroll before asserting on anything late in a page.
2. **Path keys in the tests.** The service keys files by the path `contentsOfDirectory` returns (`/private/var/…`), while the test helper built `/var/…`. Most first-run test failures came from this one mismatch. **Fix:** the helper matches by file name. Cost: one test run.
3. **Real bugs the tests found:**
   - `Tailer` dropped the bytes buffered from an earlier chunk when it computed a line's end offset (off by the fragment's length).
   - A rejected file's count was added before today's counters reset, so it was lost.
   - The move was logged after the state write, which raced the test.

   Each fix cost one run.
4. **SwiftLint:**
   - complexity in `LineParser.parse` and the read loop;
   - `IngestService` at 678 lines (now three files);
   - `ok` names;
   - a six-parameter function;
   - two test files over length.

   One commit (7c5726c) went in with a lint failure and was fixed in the next (3baa10a).
5. **Swift 6 test friction:** a `[String: Any]` can be neither static state nor a test argument (the cases became JSON text), and `await` can't be used inside `#expect`'s autoclosure. Cost: three builds.
6. **A key-shaped literal in two tests** (`sk-…`, Q-028) was caught by `check-no-secrets.sh`. The strings are now built at run time.
7. **Global log pollution.** The new `IngestSettings` test wrote settings through a `Settings` with no pipeline. Its records reached the global `Log` and failed `LogFacadeTests` in verify run 1 (a parallel-run interaction the 20 runs before had not hit). **Fix:** its own pipeline, like `AlertSettingsTests`.

## Verify and CI failures
- **Verify run 1 (`TB_UI_TESTS=0`):** `FAIL 0.2 swift test` (item 7).
- **Verify run 2:** `FAIL 5.5 StartupSequenceTests lists the glyph step`.
  - **Cause:** 5.5 greps `"daily activity", "glyph"` on one line, and the step list had been wrapped. The guard sweep (PM-5.3-4) covered 2.1 and 5.1 but not 5.5.
  - **Fix:** the list is back on one line.
  - **Lesson:** sweep for every check that names the file being edited, not only those that name the changed literal.
- **Verify run 3 (`TB_UI_TESTS=0`):** every stage check `ok` (1 250); only D13 failed, before this file existed.
- **CI run 1** (PR #32, 8e58c78): the tests did not compile on Swift 6.1. `try #require(LineParser.parse(…).get())` in two `ObservationTests` cases failed with "call can throw, but it is not marked with 'try'": 6.1's macro expansion calls the throwing `get()` without `try`, and the local toolchain accepts it. **Fix:** the `#require` was redundant (the value is not optional) and was removed (7042ee5).
- **CI run 2** (7042ee5): the Release app build failed with "actor-isolated property 'folder' can not be referenced from the main actor" (`SettingsView`). Swift 6.1 does not allow a synchronous read of an actor's `let` from another isolation; the local toolchain does. **Fix:** `nonisolated let folder` (d86d9bf). This is the same class as PM-7.1-7.
- **CI run 3** (d86d9bf): green.
- **The UI run (two new suites):** the harness column below the fold (item 1); fixed in d07aacc.
- **Final verify** (`scripts/verify-stage.sh 7.2`, every UI suite, since the branch touches `AppModel` and `Startup`, Q-047): `STAGE 7.2 OK`, 1 281 checks `ok`; UI 21 tests, 0 failures, in 17 min.

## Deviations from the docs
- **04:** the FSEvents flags add 06's `NoDefer`; the main queue delivers the events; polling is only the fallback; the daily activity gains a `harness drift` step.
- **05:** the OpenRouter per-response row; harness spend only for USD accounts; inferred days count as spend.
- **06:** the DoD counts rows per distinct request id; the folder sits in the database's support folder.
- **08:** the Harness reports group's copy; harness rows and badges; the empty By-app link.
- **11:** `IngestTailerTests` extras; E2E-3's details.
- **14 § 7.2:**
  - the inventory: three `IngestService` files, `HarnessNormalizer`, `Attribution+Harness`, the stage scripts touched;
  - A3 is asserted inside E2E-3.
- **Earlier stage scripts:**
  - 2.1's and 5.1's step lists include `ingest`;
  - 7.1's "only the key badge" check now checks that `key` exists.

## Judgment calls
- Q-049 · harness-ingest rules the docs leave open. These include:
  - FSEvents on the main queue;
  - the folder's location;
  - field failures logged as `bad_json`;
  - bucket pricing;
  - USD-only harness spend;
  - the inferred, split and drift rules;
  - the Sources group's copy;
  - E2E-3's setup.

## Carry-forward actions
- PM-7.2-1 · agent · 9.1 · `tb.retention.rawHarnessDays` can be as low as 7, but split and harness weights read `harness_event` over ranges up to 90 days. When 9.1 purges raw events, the split must read rolled-up weights or the By-app table loses its split for older days.
- PM-7.2-2 · agent · 7.3 · The drift chip (`DriftChip.swift`) reads `Attribution.harnessDrift`. The `Unassigned` row 7.2 shows for harness days without lines should match 7.3's surfacing.
- PM-7.2-3 · agent · 10.2 · OpenRouter harness buckets are priced from the book, not `cost_cents` (Q-049); revisit when OpenRouter is verified.
- PM-7.2-5 · agent · every stage · CI's Swift 6.1 is stricter than the local toolchain in two more ways (PM-7.1-7): no `#require` around a throwing call, and no synchronous read of an actor's `let` from another isolation (mark it `nonisolated`). Push a draft PR as soon as a new module compiles.
- PM-7.2-6 · agent · 7.3 · The account page's lazy `SourcesStrip` grid keeps off-screen chips out of the accessibility tree. 7.3's drilldown tests scroll before asserting on late elements; if VoiceOver needs them, swap the grid for a non-lazy wrapping layout.
- PM-7.2-4 · agent · every stage · The guard sweep before a first verify greps for every stage check that names the files being edited, including multi-element literals (5.5's step list).
- Earlier actions closed here:
  - PM-6.1-3 (DeepSeek burn from harness spend; single-app inference from balance deltas): closed (649dff9, `AttributionTests.burnFromHarness`, `inferred`).
  - PM-6.2-2 (anchored xAI from harness spend): closed (649dff9, `burnFromHarness`).
  - PM-7.1-1 (split, harness, inferred and the empty-table link): closed (649dff9, cc6d7e4).
- Process actions applied: PM-7.1-3, PM-7.1-6, PM-7.1-7, PM-1.1-1, PM-1.2-3, PM-1.3-5, PM-5.3-4.
