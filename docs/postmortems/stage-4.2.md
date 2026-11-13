# Postmortem — Stage 4.2 Freshness, stale, offline; account page shell
Date: 2026-11-12 · Branch: s4.2-freshness · PR: #20 · Planned size: M · Commits: 4

## Outcome
**Stale and offline.** A card whose primary job (usage for anchored accounts, balance for direct ones) last succeeded more than `tb.alerts.staleMultiplier` × the scheduler's interval ago now dims and reads `stale · …` in `HealthLow`. The interval includes overrides and Low Power, as the scheduler uses it. Offline, the popover shows `Offline — showing last known values` and every card is under the overlay. Either state turns the menu-bar ring dashed (`glyph.dashed`).

**Account page.** A popover card, or an account row in the Dashboard sidebar, opens the account page:
- the header: glyph, label, mode chip, band pill, freshness and `Refresh`;
- the badges row (`Balance`, `Usage`, `Cost`, `Lag`), each badge with a help popover;
- the sources strip: per job ok / failed / never / n/a, last success, next run, and the last error in plain words.

The Dashboard toolbar gained `Refresh`, and sidebar rows read `Key missing`.

**DoD.** `verify-stage.sh 4.2` prints `STAGE 4.2 OK` on run 2. All 844 stage checks are `ok`, and the one `skip` is 3.6's H2 gate (Q-033). The full UI suite passed, 11 tests. D1–D12 are met; E2E-5 is `StaleOfflineUITests`. Coverage is 97.35 % (gate 97 %). H2 is still open (Q-033) and does not block this stage.

## What went as planned
- **Advisor first.** The advisor's points shaped the design before any code:
  - stale is driven by time, not only by database writes, because offline skips write nothing;
  - the threshold uses the scheduler's own interval, Low Power included;
  - the human error message is stored at the source;
  - `next …` comes from the coordinator's slots, backoff included;
  - no inert 5.3 buttons on the account page.
- **Spike before the UI test.** A 4-second spike showed that the status item exposes the `MenuBarExtra` label's `accessibilityIdentifier`, so the glyph state is asserted directly.
- **Core kept the logic.** `Freshness`, `SourceStatus`, `AccountBadges`, `PollError.humanMessage` and `Formatters.untilNextRun` are pure and fully tested in `FreshnessTests`. The views only lay them out. The coordinator and observation suites passed the 50-loop (PM-4.1-2) before the first verify: 50/50.
- **Earlier scripts dry-run up front** (PM-3.5-5). One static pass over every stage script found the four 4.2 greps that matched their own comments, and the 4.1 literal that the new `networkMonitor()` changes, before the 35-minute verify.
- **Paper was up for most of the stage.** The account page follows `8T-0`, `B1-0` and `HP-0`. PM-4.1-1 got its look.

## What went wrong
1. **The stale UI test could not find the card.**
   - **Symptom:** in both tests the popover opened, but `popover.card.openai` never appeared, so the second click closed the popover again.
   - **Root cause:** `PopoverView` put `accessibilityIdentifier("popover.cards")` on the `ViewThatFits`, which has no accessibility element of its own. SwiftUI moved the identifier onto the only card and overwrote the card's own. The 4.2 card's `isButton` trait made it a Button that carried the parent's identifier. 4.1 never queried a card, so nothing showed it.
   - **Fix:** the `popover.cards` identifier is removed (nothing used it), and the card has no button trait. Two tree-dump spikes found this.
   - **Cost:** three single-suite runs, ~15 min.
2. **A value on a `.contain` group is not exposed.** `accessibilityValue("dimmed")` on the card never reached XCUITest. The overlay now also puts the freshness text into `stale · …`. That is 08's stale formatting, and it carries the state in text, not only in opacity (08 § Accessibility). The offline test polls once online first, so the cards show last known values. **Cost:** one run.
3. **The raw cause was lost from the log.** Storing the human message in `poll_state` dropped `PollError.summary`. `LogError.desc` is only the localized description, so `PollerTests` showed that the body was in neither place. `poll.failed` now carries the redacted raw cause in `ctx.detail` (07 updated). **Cost:** one test run.
4. **A band-pill expectation.** The pill's text is exposed as the StaticText's value (`Band: unknown`), not as its label. **Cost:** two runs of the stale test (~6 min).
5. **A doc edit reverted.** A comment added to 03's `poll_state` DDL would have broken 2.1's "001 contains 03's DDL verbatim" check. It moved into 03's prose before any verify.

## Verify and CI failures
- **Verify run 1:**
  - **Failure:** `FAIL 1.3 UI-test suite: tb.general.launchAtLogin = 1`; the value was `0`. Every UI suite had passed, 11 tests (`uitest-20261112-212931.log`).
  - **Cause:** at launch the setting mirrors the login item (09), and a fresh test root has no login-item marker. `StaleOfflineUITests` sorts after `SettingsGeneralUITests`, so its launches left `0` in the shared UI-test suite that `1.3.sh` reads afterwards. 4.1's new suite (`RefreshPauseUITests`) sorts before it, which is why this did not show up earlier. This is the same class as PM-3.4-8.
  - **Fix:** `1.3.sh` no longer reads that key from the shared suite. The test asserts it after its own relaunch ("launch at login persisted"), and a static check pins that assertion. The other eight keys are not written by later suites and are still read.
  - **Cost:** one verify run (~35 min).
- **Verify run 2:** `STAGE 4.2 OK`, with D13 green because this postmortem was written before the run.
- **CI:** see the PR.

## Deviations from the docs
- **07 § Mandatory events:** `poll.failed` gains `detail`, the raw cause, redacted (Q-036).
- **03:** a prose note says `poll_state.last_error_message` holds the human message (Q-036). The DDL is unchanged.
- **14 § Stage 4.2 Inventory:** the edited files and `Components/BandDot.swift` are listed. 14 § 0.3 adds `FixedNetworkMonitor` (DEBUG) to the reachability seam's test column.
- **1.2.sh:** its "no Refresh yet" guard is retired; 4.2.sh checks `Refresh`. Its suite-value checks are replaced by the Dashboard test's own relaunch assertions (PM-3.4-8).
- **4.1.sh:** it follows Startup's `networkMonitor()`, and checks that production still returns `NWPathMonitorAdapter`.
- **Accessibility identifier `popover.cards`:** removed (see What went wrong 1).

## Judgment calls
- Q-036 — Stage 4.2's freshness, offline and account-page rules:
  - a never-polled account is not stale;
  - paused accounts follow 05 literally;
  - the threshold's interval;
  - re-evaluation on time;
  - the offline overlay text;
  - the offline test seam;
  - the human error message and `ctx.detail`;
  - the strip's entries and words;
  - badge help sentences;
  - the header's scope;
  - toolbar `Refresh`;
  - card click;
  - identifiers;
  - PM-4.1-5;
  - PM-3.4-8;
  - `TB_UI_ONLY`.

## Carry-forward actions
- PM-4.2-1 · agent · 5.3 · The band pill and sidebar dot show `unknown` until bands exist. When 5.3 adds bands, extend `StaleOfflineUITests`, or 5.3's own UI test, to assert the pill's band word. Check that the stale overlay keeps the band's last value (05: "the band keeps its last value").
- PM-4.2-2 · agent · 4.3 · The `cost` source reads `never` with no next run until the daily activity exists. When 4.3 runs cost polls, assert `Cost · ok · HH:mm` on the account page, and decide whether the strip shows the daily run's next time. Status: closed in 4.3 (451fb19). `DailyRunNowUITests` asserts `Cost · ok · HH:mm`; no next time, because the system scheduler exposes none (Q-037).
- PM-4.2-3 · agent · 5.5 · `glyphState` is `dashed` or `solid`. 5.5 adds `notched` and must order the three, e.g. dashed over notched when both apply, with `GlyphStateTests`.
- PM-4.2-5 · agent · process · Stage scripts must not read the shared UI-test settings suite for a value a later suite can rewrite. Any launch on a fresh test root rewrites `tb.general.launchAtLogin`, and onboarding writes `tb.ui.onboardingDone`. A test that sets a value asserts its persistence itself, after a relaunch, and the script checks that the test case passed. Before adding a UI suite, list the keys its launches write.
- PM-4.2-4 · agent · process · Never put `accessibilityIdentifier` on a container that has no accessibility element of its own (`ViewThatFits`, `ForEach`, `Group`): SwiftUI hands it to a lone child. State that XCUITest must read goes into text, or onto an element, not into a group's value.
- **Earlier actions that targeted this stage:**
  - PM-4.1-3: closed (3c2f844). The Offline banner and the dashed glyph read `isOffline`; `Freshness` adds stale.
  - PM-4.1-5: closed. Missing-key accounts keep polling (Q-036).
  - PM-3.4-8: closed (b4d82a1). `1.2.sh` is independent of later suites.
  - PM-2.2-3: progress (66abb6e). Each job's last error is in `SummaryInputs` with `ObservationTests.pollStateErrors`. Balance and ledger stay open for 5.3.
  - PM-4.1-1 (11.3): checked against Paper now that it was running. The footer rework stays for 11.3, with the findings in `stage-4.1.md`.
  - Process: PM-4.1-2 followed, with the 50-loop on Coordinator, Freshness and Observation before verify. PM-4.1-4: no recurrence: `DashboardShellUITests` passed both cases inside the full suite in run 1.
