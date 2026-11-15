# Postmortem — Stage 5.5 Menu bar glyph completion & metric
Date: 2026-11-15 · Branch: s5.5-glyph-metric · PR: #27 · Planned size: S · Commits: 3

## Outcome
The menu-bar ring is notched while any account is `low` or `critical`; dashed (stale or offline) still wins. It is solid otherwise.
- **Step 8:** startup step 8 (`glyph`) reads `band_state`, so the glyph shows the last known state from launch until the first polls. An account with no poll yet keeps its stored band.
- **Metric:** 09 `tb.menubar.metric` shows beside the glyph at most 64 pt wide: `minRunway` as `12d`/`30h`, `minRemaining` as `$42`, `todaySpend` as `$3.10`. The glyph's accessibility label carries it (`TokenBe, 28h`).
- **The rule is Core logic:** `GlyphState` and `MenuBarMetric` in `Model/GlyphState.swift`, tested by `GlyphStateTests`.

This stage closes phase 5. Its verify ran the whole UI suite once, as the owner asked (Q-041), including the UI tests deferred from 5.2–5.4. D1–D13 are met. Gate H2 is still open (PM-3.6-1).

## What went as planned
- `GlyphState.state` orders `dashed` > `notched` > `solid` (PM-4.2-3). Persisted bands decide only for accounts that have not been polled.
- The UI test passes the metric as a launch argument, so the shared UI-test settings suite is not changed (PM-4.2-5).
- The smoke run first (PM-4.3-1): `PopoverEmptyStateUITests` passed in 19 s before the new suites ran. The disk had 100 GiB free (Q-039).

## What went wrong
1. **The Day-1 card put `Collecting…` in row 2 (`AnchorRunwayUITests`, 5.3's code).** **Root cause:** the runway metric's text was `Collecting…`, so `CardRows` treated Day-1 as a runway value, and the pinned runway kept row 2. Q-042 intended the remaining amount there. **Fix:** Day-1 gives the runway no value; `Collecting…` closes row 3. Cost: two UI runs.
2. **The menu-bar metric was invisible to XCUITest.** A `MenuBarExtra` status item exposes only the glyph image's label (as its `title`), not the text beside it. **Fix:** the glyph's label carries the metric (`TokenBe, 28h`), which also helps VoiceOver (Q-044), and the test reads the item's title. Cost: three UI runs (one only to read the values).
3. **Assertions that assumed the default formatting.** The card read `≈ $100,00 ± 0,00`. The owner's locale uses a decimal comma, and `SettingsGeneralUITests` leaves `tb.ui.hideCents` off in the shared suite. The pill's word was in the element's value, not its `label`. **Fix:** prefix and `±` checks; the shared `text()` helper. Cost: one UI run.

## Verify and CI failures
- New suites run one at a time before the full run (cheaper than a 40-minute cycle): `AnchorRunwayUITests` failed 4 times and `GlyphMetricUITests` 3 times (items 1–3). `NotificationsSettingsUITests` passed first time.
- Full verify (UI on, closes phase 5): see the PR body and `phase-5.md`.

## Deviations from the docs
- **14 § Stage 5.5:** the inventory names every touched file (the Core `GlyphState.swift`, step 8 in `Startup`, `fetchBandStates`).
- **Startup step 8** is a named step (`glyph`) in `StartupSequenceTests` (D7).
- **Paper:** not consulted (not running). The 64 pt cap and the compact forms follow 08's text (Q-044).

## Judgment calls
- Q-044: step 8's reach, the compact metric forms, USD-only `todaySpend`, the metric in the accessibility label, and the launch-argument UI test.

## Carry-forward actions
- PM-5.5-1 · agent · 11.3 · Check the metric's look in the real menu bar against Paper `7P-0` (a 64 pt cap, monospaced digits) once Paper is available.
- Earlier actions that targeted this stage:
  - PM-4.2-3: closed (`GlyphStateTests.states`).
  - PM-5.3-2: closed (`AnchorRunwayUITests` and `OnboardingUITests` ran in this stage's full UI run).
  - PM-5.3-3: closed (step 8).
  - PM-5.4-1: closed (`NotificationsSettingsUITests` ran).
  - PM-5.2-2: closed (the full UI suite ran at the end of phase 5).
  - Process: PM-4.3-1 followed (smoke first); PM-5.1-5 standing; PM-5.3-4 followed (no earlier guard needed a change for 5.5).
