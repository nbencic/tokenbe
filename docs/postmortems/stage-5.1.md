# Postmortem — Stage 5.1 Price book
Date: 2026-11-13 · Branch: s5.1-price-book · PR: #22 · Planned size: M · Commits: 5

## Outcome
TokenBe now prices models from a bundled snapshot of the LiteLLM price map. 3,563 chat entries ship, 3,326 of them priced. The snapshot is installed at first launch (`price.feed_ok source=bundled`, one `price_snapshot` row) and refreshed once a day by the daily activity's `price refresh` step, placed after `cost polls` and before `db backup`.
- The fetch sends the stored ETag as `If-None-Match`, times out after 10 s, caps the body at 20 MB and skips a body with the current sha256.
- A failure, a body that does not parse or an O-6 shape change keeps the current snapshot. Snapshots are pruned to 4.
- `PriceBook.lookup` follows 05's six steps with V5.
- Settings → Sources → Price book has:
  - the feed switch, the snapshot line and `Refresh now`;
  - `Stale after`;
  - the overrides list with `+`, `−` and `Reset to feed`.
- Advanced edits the feed URL, and each account page shows `Prices · <date> · ok|stale`.

D1–D13 are met. Gate H2 is still open (PM-3.6-1); it does not block this stage.

## What went as planned
- Core is `Pricing/{PriceEntry,Lookup,PriceFeedFetcher,PriceBook}.swift` and `Store/Repository+Prices.swift`, tested on the real database with a stub transport and a settable clock. `PriceFeedTests` covers the bundled seed, 304, sha256 dedupe, the same-day replace, all six failure kinds, prune, the feed switch, staleness and overrides.
- Integer rates: picodollars per token (Q-038). `PriceLookupTests.bundledSnapshot` proves that no positive rate in the shipped file rounds to 0, which V5 would otherwise silently turn into "unpriced".
- The advisor's pre-checks held:
  - startup step 4 never throws;
  - a feed failure is a warn, not a failed daily step (D10 zero-error);
  - the same-day version collision;
  - staleness measured from the last successful check.
- PM-4.3-1: the `PopoverEmptyStateUITests` smoke test passed before any UI work.

## What went wrong
1. **The bundled file could not be downloaded from the agent session.** `curl` is denied there. The script was written, and the owner ran `! scripts/update-bundled-prices.sh` (3,563 entries, sha256 `5a21f8…`). Cost: one round trip with the owner. The rest of the stage went ahead while waiting.
2. **A swiftlint false positive.** `tokenbe_no_silent_catch`'s regex `try\?` matched `PriceEntry?` in a return type. **Root cause:** the regex has no word boundary. **Fix:** `PriceBook.lookup` returns `Lookup.Hit?`, which also exposes the step. The regex is left alone (PM-5.1-2). Cost: one lint cycle.
3. **A test in the wrong type.** Rate cases appended at the end of `FormattersTests.swift` landed inside `PopoverTrackerTests`, which shares the file, and the build failed. **Fix:** moved them inside `FormattersTests` (6026477). Cost: one test run.
4. **The UI test runner was killed (`signal kill`) when it queried the overrides `Table`.** The table sat inside a grouped `Form`. No crash report was written, and the runner died within a second of the query. **Root cause:** not fully proven. The SwiftUI `Table` inside a `Form` section is the only new element in that step, and removing it fixed the run. **Fix:** plain selectable rows (6f0ffd5). Cost: two UI-suite runs (about 2 min).

## Verify and CI failures
- Verify run 1 (6f0ffd5, UI on: the branch changes app code): failed at `0.1 swiftlint --strict`. `PriceBookUITests`'s test body was 53 lines (limit 50) after `−` was added. **Fix:** the add and remove steps moved into a helper.
- Verify run 2: see the PR body for the summary lines.

## Deviations from the docs
- **07:** ctx additions for `price.feed_ok` (`source`, `changed`, `version`), `price.override_set` (`action`), `price.parse_failed` (`version` or `model`) and `price.stale` (`version`). Q-038.
- **03:** a note on the fetched-snapshot version, the same-day replace, and `fetched_at` moving on a 304 or unchanged body. Q-038.
- **14 § Stage 5.1:** the inventory names every touched file; step 5 states the position (after `cost polls`, before `db backup`).
- **09:** `tb.price.feedURL`'s `SettingSpec.tab` is now `.advanced`, matching 09's "editable in Advanced only". 09's text is unchanged.
- **Paper `10V-0`:** row 2's "Edited in Dashboard → Pricing" is not built (01/08 have no such page). The overrides list sits in Sources, as 08 says. `N unpriced` in the snapshot line arrives in 5.2 (PM-5.1-1).
- **`HTTPRequest.timeout`:** a new optional field (02's 10 s), applied as `URLRequest.timeoutInterval`.

## Judgment calls
- Q-038: the rate unit, the override JSON and its UI units, lookup with V5, snapshot versioning and staleness, failure reasons, startup step 4 and the daily step, the 07 ctx additions, the Paper/08 reconciliation, and the strip chip.

## Carry-forward actions
- PM-5.1-1 · agent · 5.2 · Add `N unpriced` to the Price book snapshot line once unpriced models are counted. Reprice on a snapshot change (and on an override change, Q in 5.2), which closes PM-3.4-3.
- PM-5.1-2 · agent · 11.2 · `tokenbe_no_silent_catch` uses `try\?` with no word boundary, so it flags any identifier ending in `try` followed by `?` (`PriceEntry?`, `Registry?`). Change it to `\btry\?` with a lint self-test.
- PM-5.1-3 · agent · process · Do not nest a SwiftUI `Table` in a grouped `Form` in Settings; use plain rows. When a UI test runner dies with `signal kill`, suspect the accessibility tree of the newest view first.
- PM-5.1-4 · agent · process · Network fetches (`curl`) are denied in agent sessions. A step that needs a download goes in a script the owner runs with `! <script>`; ask for it at the start of the stage, not at the end.
- Earlier actions that targeted this stage:
  - PM-4.3-3: closed for 5.1 (6026477; `4.3.sh`'s order check now includes `price refresh`). Re-targeted → 9.1 (roll-ups) and 9.4 (update check), as planned.
  - PM-3.4-3 (reprice provider rows): re-targeted → 5.2, where `repriceUsage` lives (14 § Stage 5.2 step 2).
  - Process: PM-4.3-1 (smoke run first) followed; PM-4.3-2 (tests pass a `logPipeline`) followed in `PriceFeedTests`; PM-4.2-4 (identifiers only on combined elements, the override rows) followed; PM-4.2-5 (no shared setting read) followed: the UI test changes no shared setting; PM-4.1-2 (50-loop) does not apply, since no new suite depends on timing (`ManualDate`).
