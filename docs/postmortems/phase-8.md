# Postmortem — Phase 8 Dashboard
Date: 2026-11-17 · Stages: 8.1 (#35), 8.2 (#36), 8.3 (#37), 8.4 (#38)

## Outcome vs. phase map
14 § 0.5: "Dashboard complete per 08." Met, item by item:
- **Overview (08 § Overview 1–5):**
  - headline and runway board (5.3);
  - **Spend by day** chart (8.2), with per-day totals that VoiceOver reaches (8.4);
  - Apps this period (7.3);
  - **Cache savings** tile (8.2).
- **Account page (08 § Account detail):**
  - numbers strip and By app (5.3, 7.1–7.3);
  - **By model** with drift and `unpriced` (8.1), and `ledger.drift` daily (8.1);
  - Sources strip (4.2, non-lazy since 8.1);
  - ledger (5.3).
- **Toolbar (08 § Dashboard window):** range picker and Refresh (1.2, 4.2); **Export…**, a CSV of the page's table, each cell as shown (8.3).
- **08 § Accessibility (8.4):**
  - figures spoken in words with their titles;
  - the band never colour only;
  - popover text size to `xxLarge`;
  - Reduce Motion pulses;
  - keyboard-navigable tables;
  - XCTest's accessibility audit in the UI tests.

  The owner's VoiceOver and Inspector pass is open (PM-8.4-1, 11.3).
- **Verification:**
  - **Core:** `DriftTests`, `CacheSavingsTests`, `ChartDataTests`, `CSVExporterTests`, `SpokenFormattersTests`; 551 tests in 83 suites at the end of 8.4.
  - **App:** `ByModelUITests` (E2E-8), `DrilldownUITests` (chart, tile, export, day totals), `AccessibilityUITests`.

## Patterns across stages
1. **SwiftUI on macOS differs from its documentation and from iOS, and only a run shows it.** This happened in every stage:
   - 8.1: a lazy grid builds no off-screen cells.
   - 8.2: a category axis ignores `AxisMarks(values:)`, and chart annotations are not exposed to accessibility.
   - 8.3: the save panel hides the `.csv` extension.
   - 8.4: a `Text`'s label replaces its value; `GridRow` modifiers reach every cell; Esc is the exit command; text styles do not grow with `dynamicTypeSize`.

   **What held:** a short probe or a single-suite run before building on an assumption. It cost about one minute each time, against a 20–30 min full verify. 8.4's advisor-ordered probe settled the design before any view changed.
2. **Earlier stage scripts guard the future, and break when it arrives.**
   - 8.3's sweep failed three times, one stale check per run: 1.2's and 4.2's `no Export yet`, and 7.3's exact-text footer grep.
   - 8.4's sweep passed on its first run, after the scripts were grepped for the control names and rewritten expressions first (PM-8.3-2).
   - 1.3.sh still guards `Export`, `Import`, `Check for updates` and `Reset all` (PM-8.3-1, phase 9).
3. **Assertions on visible text bind tests to presentation.** 8.4 made every figure speak words, and four suites that read `≈ $…` had to change. The `text()` helper reads the accessibility value, which on macOS is the label, so a test of a figure now asserts what VoiceOver hears. That is the contract 08 states.
4. **Process rules from phase 7 held.**
   - Each pushed head was gated on lint (PM-8.2-5); 8.2 learned that rule from one red CI run.
   - Merges waited for green CI selected by SHA.
   - `caffeinate` was held and the lock checked before UI runs, and no runner was killed (89–107 GiB free).
   - No stage changed a shared file, so Q-047 selected 6 to 18 suites instead of all 24.
5. **Screenshots are the owner's screen.** 8.2's diagnostic `app.screenshot()` captured the whole display, and it was deleted at once. Since then only `app.windows.firstMatch.screenshot()` is used (PM-8.2-3), and 8.3 and 8.4 needed none.

## Plan and doc changes
- **14:**
  - § 8.1–8.4 inventories and tests completed (D1);
  - § 13.6's test matrix de-duplicated (8.3);
  - § 8.4's Inspector line names `performAccessibilityAudit` and the owner checklist.
- **05:** cache savings (8.2); drift mapping (8.1).
- **08:**
  - By model (8.1);
  - chart tooltip and USD-only (8.2);
  - `Export…` per page (8.3);
  - § Accessibility's words, band word, scaled cards and table keys (8.4).
- **Judgment calls:** Q-051 (drift), Q-052 (chart and savings), Q-053 (CSV export), Q-054 (accessibility).
- **Proposed for later phases:**
  - 9.2 retires 1.3.sh's `Export` and `Import` guards with its controls (PM-8.3-1);
  - 11.3 runs the owner's accessibility checklist and settles the header contrast (PM-8.4-1, PM-8.4-2).

## Gates and risks
- **H2 (OpenAI) and H3 (DeepSeek, xAI) recordings:** open (owner). Drift's line-item mapping and the cache sources run on synthetic fixtures (PM-8.1-1).
- **Risks for phase 9:**
  - 9.1's roll-ups must keep the chart's daily sums and Anthropic's cache savings for older days (PM-8.2-4, PM-7.2-1).
  - 9.2's `Export CSV (all tables)` is the machine-readable export. 8.3's view export writes display strings by design (Q-053), and the two must not be merged.
  - Whether the system Text size reaches SwiftUI on macOS is unknown until the owner checks (PM-8.4-1).

## Open carry-forward actions
- **Phase 8:**
  - PM-8.1-1 · agent · the H2 PR · re-check `Drift.lineItemModel` against recorded line items.
  - PM-8.1-2 · agent · 10.1 · Anthropic `description` rows carry their model.
  - PM-8.1-3 · agent · 9.5 · per-process once-per-day logs.
  - PM-8.2-4 · agent · 9.1 · roll-up rows and Anthropic cache savings.
  - PM-8.3-1 · agent · 9.2, 9.4, 9.5 · retire 1.3.sh's "not yet" guards with their controls.
  - PM-8.4-1 · Nikola · 11.3 · Q-054's accessibility checklist.
  - PM-8.4-2 · agent · 11.3 · the popover header's contrast against Paper.
  - PM-8.2-3, PM-8.2-5, PM-8.3-2, PM-8.4-3 · agent · every stage · process.
- **Phase 7 and earlier (unchanged):**
  - PM-7.1-4 (11.3), PM-7.1-5 (11.5), PM-7.2-1 (9.1), PM-7.2-3 (10.2), PM-7.3-4 (11.3), PM-7.3-5 (9.5);
  - PM-6.1-1 and PM-6.2-1 (the H3 PR), PM-6.1-4 (9.1), PM-5.2-3 (accepted), PM-5.4-2 (9.5);
  - process: PM-7.1-6, PM-7.1-7, PM-7.2-4, PM-7.2-5, PM-7.3-1, PM-7.3-2.
