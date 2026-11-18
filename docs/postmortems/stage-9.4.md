# Postmortem — Stage 9.4 Update check
Date: 2026-11-18 · Branch: s9.4-update-check · PR: #42 · Planned size: S · Commits: 5

## Outcome
02 § Update check runs as the daily activity's `update check` step, after the price refresh (04):
- **The request:** one `GET` to GitHub's latest-release endpoint per UTC day, while `tb.update.checkEnabled` is on.
- **The compare:** `tag_name` against the bundle version as semver, with the `v` stripped.
- **What it writes:** `tb.update.lastCheckedAt` and `tb.update.latestSeen`.
- **The log:** `update.check_ok {latest, current, newer}` or `update.check_failed` (warn).

A newer release that hasn't been skipped shows `Update available` with `Open release page` and `Skip this version` in three places: in Privacy, under the new `Check for updates daily` row with 08's caption; at the top of the Overview; and above the popover footer. Nothing is downloaded or installed (D-no-sparkle). D1–D13 are met. No H-gate belongs to this stage; H2 and H3 stay open (owner).

## What went as planned
- **The advisor's review settled five points before any code:**
  - the Debug bundle's version (`0.1.0`, parsable);
  - 08's "one GET a day" against `Run daily tasks now`;
  - the fixture transport's answer to an unrouted host (`noFixture` → a warn, never the network);
  - no `https://` in doc comments;
  - a UI test that seeds a version new on every run instead of resetting settings.
- **Each test passed on its first run:**
  - `UpdateCheckerTests` (6 cases, after one compile fix);
  - `UpdateCheckUITests` (1 min).
- **PM-9.3-2 held.**
  - Before the first full verify: the coverage gate (97.12 %), a grep of the stage scripts for globs over the folders this stage writes into and for the expressions it changed, and a dry run of 1.3, 4.3 and 9.4.
  - The dry run caught an over-escaped `\u{2014}` in 9.4.sh's copy check before any verify ran.
- **Carry-forwards.** PM-4.3-3 closed: the step sits after the price refresh, and 4.3.sh's order check names it. PM-8.3-1's `Check for updates` guard is retired with its control.

## What went wrong
1. **`DailyRunNowUITests` failed: "the weekly check waits for the 7th run".**
   - **Symptom:** the first targeted UI run of this stage found `db.integrity_check` in the test's daily run.
   - **Root cause:** the run number is `tb.daily.runCount + 1`, read from the shared test settings domain. Every earlier run of the test had advanced it (9.1–9.3 ran it six times), and on a multiple of 7 the weekly gate opened. It was a latent one-in-seven flake from 4.3, not a change of this stage; this stage's new `update check` step didn't affect it.
   - **Fix:** the test pins `-tb.daily.runCount 0`, so it is always run 1. It passed alone right after.
   - **Cost:** one targeted rerun.
2. **Two compile and lint slips.** `TransportError` has no `.offline` (it is `.urlError(URLError)`), and a `CodingKeys` nested two levels deep broke the `nesting` rule. **Fix:** the release DTO moved to file scope. Each cost one rebuild.
3. **`AppEnvironment.init` could not build the main-actor `UpdateModel`.** **Fix:** the init is `@MainActor`; `Startup` builds it on the main actor already. One app build.

## Verify and CI failures
- **Core and lint:** 6 tests in `UpdateCheckerTests` passed; the full Core run had 582 tests in 87 suites; coverage 97.12 %; lint clean after What went wrong 2.
- **UI, targeted:** UpdateCheckUITests passed. DailyRunNowUITests failed once (What went wrong 1), then passed alone.
- **Guard sweep** (`TB_UI_TESTS=0 verify 9.4`): `STAGE 9.4 OK` on the first run, with 1 486 checks passed and no stale guard.
- **Full verify:** see the PR body. `AppEnvironment.swift` is a shared file, so Q-047 selected every suite.
- **CI:** the head that carries this file is checked by SHA before the merge.

## Deviations from the docs
- **02 / 09 / 14 name the badge's places differently** (02: Settings and the Overview; 09: Privacy and the popover footer). It is in all three (Q-058).
- **The release page.** The badge opens the latest check's `html_url` only when it is a TokenBe release page, else `releases/tag/v<latestSeen>` (Q-058).
- **14 § Stage 9.4:** the Inventory now lists the files, and the Tests line the cases and the UI test.

## Judgment calls
- Q-058: the update check rules the docs leave open:
  - one GET per UTC day;
  - semver rules;
  - failures, a 404 before the first release included;
  - the request;
  - how the release page is checked;
  - the badge's places and button names;
  - hiding the badge while checks are off;
  - the Privacy row;
  - the UI test's seeded version.

## Carry-forward actions
- PM-9.4-1 · agent · 11.5 · Before 1.0 the repository has no release, so every daily check logs `update.check_failed` (HTTP 404) at warn. After the first release, confirm one `update.check_ok` on the owner's Mac. During the H5 soak, a 404 means the check runs before the release exists; Q-058 records why that is expected.
- Earlier actions that targeted 9.4:
  - PM-4.3-3: closed (the `update check` step; 4.3.sh's order check). Status edited in stage-4.3.
  - PM-8.3-1: closed for 9.4 (`Check for updates`); open for 9.5 (`Reset all`). Status edited in stage-8.3 and phase-8.
  - PM-9.3-2: closed (applied; What went as planned).
- Still open:
  - PM-9.3-1 (11.3);
  - PM-9.2-1 (11.2);
  - PM-9.1-1 (11.1);
  - PM-8.1-1 (the H2 PR);
  - PM-8.1-2 (10.1);
  - PM-8.1-3 (9.5);
  - PM-8.4-1 (owner, 11.3);
  - PM-8.4-2 (11.3).
