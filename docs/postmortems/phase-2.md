# Postmortem — Phase 2 Storage
Date: 2026-11-10 · Stages: 2.1 (#9), 2.2 (#10)

## Outcome vs. phase map
14 § 0.5: "DB created, migrated, observed; backup/integrity on demand."
- **Created:** met. `tokenbe.sqlite` uses 03's PRAGMAs on every connection, in a `0700` folder (2.1).
- **Migrated:** met. 001 is 03's DDL verbatim, diffed on every verify, plus the two seed rows. The migrator is forward-only with one transaction per file. A failure shows the fatal alert and quits without touching the file (2.1).
- **Observed:** met. `ValueObservation` → `SummaryInputs` → `AccountSummaryBuilder` → `AppModel` (2.2). The inputs are `account` only for now and grow per stage (Q-025).
- **Backup/integrity on demand:** met. Settings → Advanced `Run integrity check now` and `Back up now`, with result sheets (2.2). The launch `quick_check` repairs a corrupt file from `.bak` or starts a fresh database (2.1).

## Patterns across stages
1. **UI-test shared state, again, in a new place.** Phase 1 learned that 09 values one UI test leaves can break another stage's check (PM-1.3-2). Phase 2 hit two new carriers:
   - AppKit's remembered Settings tab (2.2, PM-2.2-1);
   - a suite reset by a later test, which erased what a stage script read afterwards (2.2, PM-2.2-2).

   The root cause is the same: cumulative verify runs every suite against one shared settings domain and one window-state store. The durable fix is that each test asserts its own effects inside its own root, and leaves global state as it found it.
2. **The plan's Verify lines can conflict with its own D10.** 2.2's Verify named the owner's real support folder. 2.1 had already added `real_support_unchanged`, which made the conflict visible before anything was written there. Each stage's Verify line is now read against D10 before it is turned into a check (Q-025).
3. **Unattended UI runs depend on one-time owner setup.** In 2.1, two verify runs were lost to the Automation Mode password prompt until PM-2.1-5 was done. Phase 2 needed no other owner action.
4. **Test-only isolation of logging pays off.** Every store API takes a `logPipeline:` (PM-2.1-2). The observation failure test asserts its `ui.error` record without touching the process-wide `Log`, and the 50-run loops of both stages stayed green.

## Plan and doc changes
- Applied during the phase:
  - `03`: the `auto_vacuum` comment (Q-024).
  - `14`: step 5's Repository scope (declared per aggregate as implemented; `observeSummaryInputs` moved to 2.2); the `FixtureDBBuilder` path (Q-024); 2.2's Verify under the test root (Q-025).
- Q-024 and Q-025 logged.
- `verify-stage.sh` gained the `real_support_unchanged` guard.
- Proposed for later phases:
  - 4.1–5.3: each stage that fills an `AccountSummary` field adds its table to `SummaryInputs`, with an observation test (PM-2.2-3).
  - 9.x: the weekly integrity check's restore policy, closing the pool at quit, and the idle `wal_checkpoint(TRUNCATE)` / `optimize` (PM-2.1-4).

## Gates and risks
- **No human gate in Phase 2.** PM-2.1-5 (`automationmodetool`) was done by the owner on 2026-11-10.
- **H2** (OpenAI fixture recording) is next, at 3.6. Phases 4–5 can proceed on synthetic fixtures while it is open.
- **Risks for Phase 3 (Accounts):**
  - Keychain access in UI tests: the test root does not isolate Keychain. 3.2's `KeyStore` seam must keep every UI test on `InMemoryKeyStore` or a test-only service name, never the owner's real items.
  - The first outbound HTTP (3.1): `check-no-secrets.sh`'s host allowlist and "no provider call during `swift test`" (R13) must hold from the first commit.
  - The account list is now live from the database. 3.5's onboarding is the first writer, so the empty-state ↔ cards transition gets its first real exercise there.

## Open carry-forward actions
- PM-2.2-1 · agent · process · UI tests leave AppKit/SwiftUI state as they found it, or set it explicitly.
- PM-2.2-2 · agent · process · Assert UI-test writes inside the test, from the app's log in its root.
- PM-2.2-4 · agent · process · Check 08 § Formatting rules before formatting any user-visible value.
- PM-2.2-3 · agent · 4.1–5.3 · Grow `SummaryInputs` per stage, with an observation test per added table.
- PM-2.1-1, PM-2.1-2 · agent · process · `#filePath` defaults resolve at the caller; tests never log through the process-wide `Log`.
- PM-2.1-4 · agent · 9.x · Weekly integrity restore policy; closing the pool at quit; idle checkpoint and `optimize`.
- Phase 1's open actions: PM-1.3-1, PM-1.3-2, PM-1.2-1/2/3/5, PM-1.1-1 (process); PM-1.3-3 (5.5); PM-1.3-4 (8.4 / 11.4); PM-1.2-4 (9.5); PM-1.1-3 (3.5); PM-1.1-2, superseded by PM-2.1-5, done.
- Phase 0's open actions: PM-0.1-3 (11.5); PM-0.2-3 (9.5); PM-0.3-2, PM-0.4-2, PM-0.5-1 (process); PM-0.4-3 (owner, `.env` permissions); PM-0.5-2 (owner, coverage, 11.2).
