# Postmortem — Stage 8.4 Accessibility & input
Date: 2026-11-17 · Branch: s8.4-accessibility · PR: #38 · Planned size: M · Commits: 4

## Outcome
08 § Accessibility is met (Q-054):
- **VoiceOver reads every figure in words with its title.** Core's `Spoken` turns `≈ $42 ± 3` into `Remaining, approximately 42 dollars, plus or minus 3`, `~12 d` into `about 12 days` and `CN¥57` into `57 yuan`. It is built from `Money`, the band and the runway seconds, never by rewriting display strings, and it covers:
  - the popover card's rows;
  - the numbers strip;
  - the runway board's cells;
  - the Overview headline and totals;
  - the By-app, By-model, ledger and Apps-this-period amounts;
  - the chart.
- **The band is never colour only.** The dot and pill already named it. The band-coloured headline and the band-tinted banner now end with `band <word>`, and the dot has a role.
- **Dynamic Type to `xxLarge` in the popover.** macOS text styles do not grow, so the cards scale their own point sizes (`ScaledFont`): the card figure measures 24 pt at the default size and 29 pt at `xxLarge`. The popover keeps its 360 pt width, and the apps row may take two lines.
- **Reduce Motion.** The refresh button and the four spinners (`BusyIndicator`) pulse instead of turning.
- **Keyboard.** The grid tables' rows take focus (Tab or a click); ↑/↓ move and Esc leaves. The ledger is a selectable list.
- **Carry-forwards closed:**
  - PM-8.2-2: each day's chart total is its own element, reachable without the pointer.
  - PM-8.2-1: the board's name keeps one line.
  - PM-7.3-3: the ⌥-click test waits for a finite status-item frame and logs it.
- **Audit:** XCTest's `performAccessibilityAudit` runs on the popover and the Dashboard, the scriptable part of the Accessibility Inspector pass. The rest is the owner's checklist in Q-054 (PM-8.4-1), which is not marked done.

D1–D12 are met. Gates H2 and H3 are still open (owner) and do not block. This stage closes phase 8 (`phase-8.md`).

## What went as planned
- **Probe before code** (the advisor's first step). One throwaway run of AnchorRunwayUITests showed two things before any view changed:
  - on macOS, a `Text`'s `accessibilityLabel` replaces its accessibility value;
  - a `.ignore` container drops its value.

  That fixed the design: one element per figure, whose label is `<title>, <words>`. VoiceOver hears one rendering, and the tests read the same text.
- **Core first.** `SpokenFormattersTests` (4 tests: 08's sentence, money, CN¥, estimates, runway words) passed on the first run. The full Core run had 551 tests in 83 suites.
- **The guard sweep passed on its first run** (`TB_UI_TESTS=0 verify 8.4`): 1 380 checks, with only D13 left. Before the sweep, the stage scripts were grepped for every expression this stage rewrote (PM-8.3-2), and none matched.
- **No shared file changed.** The test overrides live in a new `AccessibilityOverrides.swift`, not in `Startup`. Q-047 therefore selected 18 suites instead of all 24.
- **The draft PR went up once the stage compiled** (PM-7.2-5), and lint gated the push (PM-8.2-5).

## What went wrong
1. **macOS text styles do not grow with `dynamicTypeSize`.**
   - **Symptom:** AccessibilityUITests run 1 measured the card figure at 26 pt at both sizes.
   - **Cause:** SwiftUI's text styles on macOS have fixed point sizes.
   - **Fix:** `ScaledFont` (iOS body ratios over 17 pt, capped at `xxLarge`) on the popover cards. The card figure went back to Paper's 20 pt; run 1 had used `.title`'s 22 pt. Logged in Q-054.
   - **Open:** whether macOS passes its own Text size setting into SwiftUI is untested, because the agent never changes the owner's settings (owner checklist).
   - **Cost:** one UI run.
2. **The runway board's row was never one element.**
   - **Symptom:** run 2 found the row's label empty. A probe showed that the identifier `dashboard.runwayBoard.openai` sat on the name cell, and that the remaining cell could not be found by its own identifier.
   - **Cause:** a `GridRow` passes its modifiers to every cell. The `.accessibilityElement(children: .combine)` from 5.3 never combined anything, and the row's identifier overrode each cell's own.
   - **Fix:** the row identifier moved to the name cell, and every cell is its own element with its column title.
   - **Cost:** two UI runs.
3. **Esc did not leave the table.** `onKeyPress(.escape)` never fired, because macOS delivers Esc as the exit command (`cancelOperation:`). **Fix:** `onExitCommand`. **Cost:** one UI run.
4. **The audit took four enforcing runs to settle.**
   - **Logging-only first pass:** a labelled `Circle` (the band dot) was flagged "Unknown role". Fixed in the app with the image trait.
   - **Enforcing runs 1–3:** each found one more class, because the handler stopped at the first untolerated issue:
     - the untitled `MenuBarExtra` panel (`Dialog`);
     - contrast on the popover header's `Refreshed …`.

     **Fix:** the fourth enforcing run collected every issue, logged each one and asserted once at the end, so one run showed them all.
   - **Tolerated, as system chrome:**
     - unlabelled `NavigationSplitView` groups;
     - the panel;
     - contrast on the sidebar rows and the window title;
     - "nearly passed".
   - **Tolerated by name:** the header text (PM-8.4-2: its colour is Paper's call, 11.3).
   - **Cost:** four UI runs (about 1 min each).
5. **Full verify 1 failed DrilldownUITests, and its rerun exposed a layout regression.**
   - **Symptom 1:** the tooltip check expected ` dollars`, but with cents hidden `≈ $0.64` is `approximately 1 dollar`. The test, not the code, was wrong; it now accepts both forms.
   - **Symptom 2:** the rerun got past that check for the first time, and then the click on the Overview's `news-digest` row opened nothing.
   - **Cause:** the per-day totals element (PM-8.2-2) was a 1 pt view in the chart card's `VStack`, which added 13 pt with the spacing. That pushed `Apps this period` far enough down that the click's point fell outside the window's visible area.
   - **Fix:** the element is the chart's `.background`, so it takes no room. Drilldown then passed.
   - **Lesson:** an accessibility-only view must take no space; attach it as a background or overlay.
   - **Cost:** one full verify (about 25 min) and two Drilldown runs.
6. **Lint.** A diagnostic `print` broke `tokenbe_no_print` in the UI tests, and the card's four-member tuple broke `large_tuple`. **Fix:** `XCTContext.runActivity` for notes, and a `CardText` struct. Both were caught before the first commit.

## Verify and CI failures
- **Core and lint:** 551 Core tests in 83 suites passed. Lint violations (What went wrong 6) were fixed before the first commit.
- **Probes:** two throwaway runs of AnchorRunwayUITests (label and value exposure), reverted before any real change.
- **AccessibilityUITests alone, 10 runs:**
  - runs 1–4 failed: text size, the board row twice, then Esc (What went wrong 1–3);
  - run 5 passed with the audit only logging;
  - runs 6–9 failed on the enforced audit (What went wrong 4);
  - run 10 passed: pinned 24 → 29 pt, and both audits were clean apart from the tolerated classes.
- **Guard sweep** (`TB_UI_TESTS=0 verify 8.4`): all 1 380 checks passed on the first run, except D13 (this postmortem, not yet written).
- **Full verify 1** (Q-047 selected 18 suites): FAIL 0.4. 21 of 22 UI tests passed in 18 min; DrilldownUITests failed on `1 dollar` (What went wrong 5). Disk had 89 GiB free, the screen was unlocked, and no runner was killed.
- **DrilldownUITests alone:** run 1 failed on the row click (What went wrong 5), and run 2 passed after the background fix.
- **Full verify 2** (the same 18 suites): `STAGE 8.4 OK` with 1 414 checks passed and 4 printing `skip`. The UI suites ran 22 tests with 0 failures in 18.5 min. The ⌥-click test logged a finite frame, `(1058.0, 4.5, 36.0, 24.0)`, and passed (PM-7.3-3). Disk had 89 GiB free, and the screen was unlocked.
- **CI:** green on 6986ffe (the first pushed code) and on 4cf39c8; the head that carries this line is checked by SHA before the merge. No CI failure on the way.

## Deviations from the docs
- **08 § Accessibility:** the words VoiceOver reads, the band word on the headline and banner, the cards' own scaling, and the grid tables' keys (Q-054).
- **14 § 8.4:** the inventory (D1) and the tests. The Accessibility Inspector line now names `performAccessibilityAudit` as the scripted part, and the owner checklist as the rest. 14 had said "manual checklist … marked done", but the agent cannot mark a VoiceOver listening pass done without doing it, so the checklist stays open (PM-8.4-1).
- **UI tests that read figures** (AnchorRunway, DirectBalance, Onboarding, Drilldown) now assert the spoken text. The banner's label ends with `band <word>`.

## Judgment calls
- Q-054: the words; one element per figure; grid rows; the band word; Dynamic Type via `ScaledFont`; the DEBUG test overrides; Reduce Motion and `BusyIndicator`; the keyboard model; the audit and its tolerated classes; the owner checklist.

## Carry-forward actions
- PM-8.4-1 · Nikola · 11.3 · Q-054's owner checklist: a VoiceOver pass over the popover, Overview and an account page; macOS Text size (does the popover grow?); Reduce Motion; an Accessibility Inspector audit of the popover, the Dashboard and Settings. Tick the boxes in Q-054. If the system Text size does not reach the popover, decide in 11.3 whether `ScaledFont` should also follow it.
- PM-8.4-2 · agent · 11.3 · The popover header's `Refreshed …` fails the contrast audit on the header material, while the cards' same style only "nearly" passes. Settle its colour against Paper, then drop its name from AccessibilityUITests' tolerated list. Widened in 9.1: the audit also tolerates contrast on ANY element without an identifier, which is wider than Q-054's "sidebar rows and window title"; 11.3 narrows that predicate to the window title (or names each element it tolerates).
- PM-8.4-3 · agent · every stage · A `GridRow` passes its modifiers to each cell: put a row's identifier or accessibility grouping on a cell, never on the `GridRow`. Collect every audit issue before asserting. (Process.)
- Earlier actions closed here: PM-7.3-3 (18b8290), PM-8.2-1 (18b8290), PM-8.2-2 (18b8290). Their original files are marked.
- Earlier actions that targeted 8.4: PM-7.3-3, PM-8.2-1, PM-8.2-2 (all closed).
- Still open from earlier stages: PM-8.1-1 (H2 PR), PM-8.1-2 (10.1), PM-8.1-3 (9.5), PM-8.2-4 (9.1), PM-8.3-1 (9.2, 9.4, 9.5).
- Process actions applied: PM-7.1-3, PM-7.1-6, PM-7.1-7, PM-7.2-5, PM-7.3-1 (`caffeinate` held, `IOConsoleLocked` false before every UI run), PM-7.3-2 and PM-8.3-2 (sweep first; the scripts grepped for rewritten expressions), PM-8.2-3 (no screenshot this stage), PM-8.2-5 (lint gated every push).
