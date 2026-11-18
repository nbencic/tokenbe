# Postmortem — Stage 5.4 Notifications
Date: 2026-11-15 · Branch: s5.4-notifications · PR: #26 · Planned size: M · Commits: 2

## Outcome
TokenBe now sends macOS notifications per 08:
- when an account turns `low` or `critical`;
- when an anchored account has had no anchor for over 24 h;
- when its data has been stale for over 6 h.

**Rules**
- Each kind has its 09 switch.
- An account gets at most one notification per kind per 24 h.
- A snoozed provider gets none.
- Quiet hours (default 23:00–07:00, wrapping past midnight) hold notices and send them when they end, logged `suppressed_by_quiet_hours: true`.

**Actions**
- Notifications carry `Open` (the account's page) and `Snooze 24 h` (`tb.alerts.snoozedUntil.<provider>`).
- Authorization is asked at the first notice, not at launch. Denied → `ui.notification_denied` and the Alerts tab banner with `Open System Settings` (O-11).

**Settings → Alerts** gains the four switches, quiet hours with their times, and `Send test notification`.

E2E-4 runs as a Core test with `RecordingNotifier`: a fixture driven to critical gives exactly one notification, and back to healthy gives none. D1–D13 are met with the UI part deferred (Q-041): `NotificationsSettingsUITests` is compiled and runs in 5.5. D10's launch checks ran. Gate H2 is still open (PM-3.6-1).

## What went as planned
- `AlertPolicy` is pure:
  - which kinds qualify, from the transitions `BandRecorder` logged;
  - quiet hours;
  - the copy.
- `AlertCenter` (an actor) owns the 24 h dedupe, the quiet-hours queue and the first-time authorization. `AlertPolicyTests` covers every rule, wrap past midnight, dedupe, the queue, denial, a failed delivery and the test notice.
- UI tests never touch macOS notifications. Under a test root the app's `FileNotifier` writes `notifications.ndjson`, the same pattern as `FileKeyStore` (Q-030). The UI test reads the test notice back from that file.
- PM-5.3-1 settled: `AlertPolicy` consumes `BandRecorder`'s transitions. A `launch` change counts, because the band really changed; restoring the same band is no change (Q-043).

## What went wrong
1. **14 contradicted itself on the `Notifier` seam.** 0.3 places it in the app, but E2E-4 needs `RecordingNotifier` in a Core test, and Core tests cannot import the app. **Fix:** the protocol moved to Core (`TokenBeCore/Notifications/Notifier.swift`), and 0.3 and the inventory are updated (Q-043). Cost: none; found while designing.
2. **A copy test expected `72 h`.** 05's formatter says `~3 d` from 48 h up. **Fix:** the test, which also uses whole dollars so no locale's decimal separator matters. Cost: one test run.
3. **Lint: `Transition.to`** is a 2-character name. Renamed to `band`. Cost: one lint run.

## Verify and CI failures
- Stage-only run 1: failed at `5.4 UI tests never reach macOS notifications`. The check looked 2 lines above `struct FileNotifier`, but the doc comment put `#if DEBUG` 3 lines up. **Fix:** 4 lines of context.
- Stage-only run 2: every 5.4 check ok; only D13 (this file) failed, as expected.
- Full verify run 1 (`TB_UI_TESTS=0`, in a separate worktree while 5.5 was built): `STAGE 5.4 OK`, 1071 `ok`, 24 `skip` (23 UI, Q-041; 1 H2). It passed first time: PM-5.3-4's guard sweep found nothing in earlier scripts to update for this stage.

## Deviations from the docs
- **14 § 0.3:** `Notifier` lives in Core. The production implementations are `UNNotifier` and, in DEBUG UI tests, `FileNotifier` (Q-043).
- **14 § Stage 5.4:** the inventory names every touched file.
- **07 `ui.notification_sent`:** `band` also takes `stale` and `test`. `suppressed_by_quiet_hours` means the notice was held and sent at the end (Q-043).
- **01 S11 "optional Shortcut":** not built. No doc defines it, and R9 forbids controls 08/09 do not list (Q-043).
- **Paper:** not consulted (not running).

## Judgment calls
- Q-043: the seam's place, the UI-test notifier, what counts as a transition, the unknown and stale clocks, in-memory dedupe, quiet-hours semantics, snooze dropping notices, the authorization moment, authored copy, and time pickers for `HH:mm`.

## Carry-forward actions
- PM-5.4-1 · agent · 5.5 · **closed (Stage 5.5)** · Run `NotificationsSettingsUITests` (Q-041). The test flips each switch and flips it back, so the shared UI-test settings suite is unchanged (PM-4.2-5).
- PM-5.4-2 · agent · re-targeted → 11.5 (Stage 9.5, Q-059: judge on the H5 soak's data) · The 24 h dedupe is in memory, so a relaunch can repeat a notice within 24 h. Revisit after the H5 soak shows whether it matters.
- Earlier actions that targeted this stage:
  - PM-5.3-1: closed, as above.
  - PM-4.3-2 followed: `AlertPolicyTests` pass a `logPipeline` through `StoreHarness`.
