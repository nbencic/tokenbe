# Postmortem — Stage 3.5 Onboarding, Accounts tab, first account
Date: 2026-11-10 · Branch: s3.5-onboarding · PR: #15 · Planned size: L · Commits: 6

## Outcome
A user can add an OpenAI account and manage it. This is the first stage with a visible product flow.
- **Onboarding** is its own 520×440 window (Q-030). It opens at first launch, or from the Empty state's `Add account…`.
  - **Step 1** shows a tile per provider from `registry.availableForOnboarding`, each with 08's caption. A provider that already has an account is disabled with `Added`.
  - **Step 2** has a secure key field with `Paste`, a label field, and 08's wrong-prefix message. `Test & continue` runs the probe with a spinner, and a failure shows its human message.
  - **Step 3** shows the mode, key count and currency, then the inline anchor (`Set anchor…` / `Skip for now`), `Launch at login` and `Done`.
- **Account lifecycle (Core).**
  - **Probe:** runs with a 10 s timeout on the injected clock.
  - **Create:** runs after a passed probe. It writes the Keychain item, the account (UUIDv7 id) with its 4 `poll_state` rows, and the discovered keys, and rolls the item back if the database refuses.
  - **Other operations:** replace key, test (both reset the circuit), remove (cascade, Keychain item, templated settings), and the anchor (`ledger_event(kind=anchor)`, `ledger.anchor_set`).
  - **`Done`** runs the first `keys` and `usage` polls.
- **Startup step 3.** It checks each account's Keychain item without reading the secret (`KeyStore.contains`). A missing item logs `keychain.missing`, and the card reads `Key missing · Fix…`, which opens Settings → Accounts.
- **Settings → Accounts** (Paper's 720 pt master-detail):
  - an editable label;
  - `Valid · tested <freshness>`;
  - `Replace key…` (a sheet reusing step 2), `Test`, `Remove account…` (destructive confirmation) and `Paused`;
  - Keys & apps, with name and hint.
- **Popover and Dashboard.** Cards show the provider glyph and `No data yet` / `never` until the first poll; the cards size the popover while they fit, then scroll. The Dashboard sidebar lists accounts with an `unknown` band dot.
- **`SummaryInputs`** now carries `poll_state` freshness and the circuit.
- **Verification.** 238 Core tests in 45 suites pass. New suites: AccountLifecycleTests, AccountSupportTests, and the `ObservationTests.pollStateFreshness` case. Two `OnboardingUITests` run in fixture mode and assert the database and key file of their own test root.

DoD D1–D11 are met; D12 by the PR's CI; D13 by this file. 238 Core tests pass, lint is clean, and the Release build is green.

## What went as planned
- The plan was reviewed before any code was written. The review caught three things:
  - the Keychain ACL / sandbox risk for UI tests;
  - that new UI-test classes run between the Dashboard test and the settings test;
  - that onboarding auto-opening would hit every existing UI test.

  The fixes were `FileKeyStore` in the test root, no settings resets in onboarding tests, and `-tb.ui.onboardingDone <true/>` by default in `makeApp`.
- 08 wins over Paper for copy, and over 14 for the Keys & apps columns (R1). Every string Paper or I added is listed in Q-030.
- The key exists only in step 2's view state, never on a view model, and is cleared after hand-off (R8). Startup never reads a secret.
- Lint ran after each slice (PM-3.4-5), and generics stayed `Sendable` (PM-3.4-7).

## What went wrong
1. **UI-test element lookups, three runs.**
   - A tile's caption is folded into the button's label.
   - The card's and the Accounts tab's container identifiers are folded into their parent group.
   - A tile element went stale when the account list arrived at launch.

   Each first looked like an app problem. The popover case cost two runs: I swapped the card list's `ScrollView` for `ViewThatFits` on a guess before a screenshot showed the popover rendering fine. The layout change was kept, and it is now covered by the test. The tests now query the rows that carry identifiers, using fresh queries. Cost: about six targeted UI runs.
2. **Earlier stages' checks and tests.**
   - `1.1.sh`/`1.3.sh` and `PopoverEmptyStateUITests` asserted that `Add account…` and the Accounts tab did not exist.
   - `2.1.sh` asserted the exact startup steps.
   - `3.4.sh` asserted the exact `Repository` line.

   Each surfaced one full verify at a time (runs 1 and 2, about 12 minutes each). Before a stage's first verify, grep the earlier stage scripts for every symbol, string and step it changes (PM-3.5-5).
3. **A debug screenshot captured the owner's screen.** It was saved to the runner's temporary folder and the scratchpad, and deleted right after use. Use `app.debugDescription` filtered to TokenBe's elements instead (PM-3.5-1).

## Verify and CI failures
- Verify run 1: FAIL at `0.4 UI tests (LaunchSmokeTests)` (the UI suite as a whole, exit 65) after 148 checks:
  - `PopoverEmptyStateUITests` still asserted that `Add account…` does not exist;
  - `OnboardingUITests` hit a stale tile element.

  Both tests were fixed; the app was unchanged.
- Verify run 2: the UI suites all passed, then verify failed at `2.1 startup step 2 is the database (04), then the login item`, after 345 checks. 2.1's exact startup-order checks (declared and logged) and 3.4's exact `Repository` line did not expect 04 step 3 (`accounts`) or `& LedgerRepository`.
  - All three checks now assert the order or the substring.
  - Stages 2.1–3.5 were then dry-run without the UI suites, reusing run 2's results; no app code had changed since. An earlier dry-run attempt had run 2.1's launches before 1.3's check and tripped 1.3 on the reset settings, which was an artifact of the ordering.
- Verify run 3: `STAGE 3.5 OK`, 678 checks across stages 0.1–3.5 and D13, the UI suites included.
- CI: PR #15 `build-test` passed on the first run (head 522961d): build, 238 tests, coverage gate, lint, event-table check, app build and the secret guard over the Release products. This file's final update re-runs CI before the merge.

## Deviations from the docs
- 08 asks for a 520×440 sheet. It is a fixed-size window, since a menu-bar app has no window to carry a sheet (Q-030). `Replace key…` is a real sheet on the Settings window.
- 14 step 2 listed Keys & apps columns "created, last used". 08 lists name and hint, and 03 has no columns for the others, so 08 wins and 14 is reworded.
- 14 Tests: the key-removal check uses the app's test key file plus `AccountLifecycleTests`, not the runner's `KeychainKeyStore` read. The Verify line asserts the test root's database through the UI test (Q-025, Q-030). 14 is reworded.
- Changed outside the inventory:
  - `KeyStore.contains`, plus `KeychainKeyStore`, `InMemoryKeyStore` and `FileKeyStore` (DEBUG);
  - `UUIDv7`, `Formatters.cents(fromInput:)`, `Transports.make(cases:)`/`cases(from:)`;
  - `PollRepository.resetCircuit`, `SummaryInputs.pollStates`, `CoreStrings.keyMissing`;
  - `ProviderGlyph`, `AppEnvironment` (keyStore, poller, lifecycle), `AppModel` (records, missingKeys, settingsTab, openOnboarding);
  - `TokenBeApp` (the onboarding window), `PopoverView`, `EmptyStateView`, `SettingsView`, `UITestSupport.makeApp`;
  - `MemoryRepository`, `PopoverEmptyStateUITests`, `1.1.sh`, `1.3.sh`, `2.1.sh`, `3.4.sh`;
  - earlier postmortems' carry-forward statuses.

## Judgment calls
- Q-030, covering:
  - the window instead of a sheet, and the launch rule;
  - copy sources (08, Paper, authored);
  - the glyph;
  - the test key store and fixture cases;
  - probe success, the timeout and create rollback;
  - startup step 3 checking existence only;
  - the summary inputs;
  - the Accounts tab details, Keys & apps columns and anchor parsing;
  - sidebar rows that cannot be selected;
  - PM-1.1-3 re-targeted.

## Carry-forward actions
- PM-3.5-1 · agent · process · Debug UI tests with `app.debugDescription`, filtered to TokenBe's elements. A screenshot captures whatever else is on the owner's screen. If one is unavoidable, crop it to the app's frame and delete it right after use.
- PM-3.5-2 · agent · process · In macOS UI tests, assert on the leaf elements that carry identifiers: texts and buttons. SwiftUI folds `.contain` containers into their parent, and button labels absorb their child texts. Re-query an element after the app may have redrawn.
- PM-3.5-5 · agent · process · Before the first full verify, grep `scripts/stages/*.sh` for each file, string, startup step and typealias the stage changes. Then dry-run the later stage scripts without the UI suite, ordered as `verify-stage.sh` orders them.
- PM-3.5-3 · agent · 4.1 · `Paused` writes `account.paused`. The scheduler (4.1) is its consumer, and `SummaryInputs` must carry it then (PM-2.2-3).
- PM-3.5-4 · agent · 10.1 · Anthropic's wrong-prefix copy, which 08 lacks: log a Q or add it to 08 when the Anthropic tile appears (from PM-3.3-1). Status: re-targeted → 10.1 in phase 3's postmortem. 14 has no stage 3.7; the Anthropic adapter is 10.1.
- Earlier actions targeting 3.5:
  - PM-3.2-1: closed.
  - PM-3.2-2: closed.
  - PM-3.3-1: closed for OpenAI, with the Anthropic part re-targeted (PM-3.5-4).
  - PM-3.4-1: closed.
  - PM-1.1-3: re-targeted → 11.2.
  - PM-2.2-3: progress (poll_state).
