# Postmortem — Phase 9 Data lifecycle & maintenance
Date: 2026-11-18 · Stages: 9.1 (#39), 9.2 (#40), 9.3 (#41), 9.4 (#42), 9.5 (#43)

## Outcome vs. phase map
§ 0.5: "Long-term durability features; startup sequence audited."
- **Retention.** 03's tiers run daily as `roll-ups`: hourly→daily, daily→monthly, the raw harness purge and balance thinning. Every total stays exact, cache savings included (9.1, Q-055).
- **Export and import.** 03's JSON document, an import only into an empty database and in one transaction, and the CSV of all tables. E2E-7 runs the round trip in the app (9.2, Q-056).
- **Diagnostics.** 07's bundle, zipped with `ditto`, never holding the database or a key (9.3, Q-057).
- **Update check.** 02's daily GitHub check and the `Update available` badge in three places (9.4, Q-058).
- **Reset and audits.** `Reset all settings…`, time-zone changes, E2E-6, `check-log-events.sh --from-tests`, and the startup sequence audited by launching the app (9.5, Q-059).

Every item of the map is met. H5 starts at the end of this phase (§ Gates and risks).

## Patterns across stages
1. **Earlier stages' checks break when later stages arrive.**
   - Three cases:
     - 9.1 rewrote an expression 8.2.sh grepped;
     - 9.3 retired the guard line 9.2.sh pinned exactly, and its new file matched 9.2.sh's `Export/*.swift` glob, which cost one full verify.
   - **Root cause:** checks written against a folder glob or an exact line also check whatever later stages put there.
   - **What held from 9.3 on (PM-9.3-2):** before the first full verify,
     - grep the stage scripts for globs over every folder the stage writes into, as well as for the names it changes;
     - dry-run every check of each stage whose files changed.

   9.4's and 9.5's guard sweeps passed on their first run. Checks written in this phase name their own files, or a pattern ("no Export/Import guard") instead of a line.
2. **A test passed here and failed elsewhere, or later, because of the environment it ran in.**
   - 9.2: `(x ?? nil) != nil` on a `Date??` resolved differently in Swift 6.1 (CI) and 6.4 (this Mac). Built here, the app showed Remaining before an account's first poll. CI caught it, and the gate now flattens explicitly.
   - 9.4: `DailyRunNowUITests` read its run number from the shared test settings domain, so about every 7th run opened the weekly gate. It now pins the count.
   - **What held:** asserting the gate itself (`nil` before the first poll) instead of only comparing two results, and pinning by launch argument any shared-domain value a test depends on.
3. **The coverage gate sits just above its floor.** Core is at about 97.1 %. 9.3's new file with untested error paths sank it to 96.9 % (one CI run and one full verify). From 9.4 the gate ran before the first verify, and each new Core file shipped tests for its failure branches.
4. **The docs disagreed with themselves, and each case got a Q and a doc fix in the same PR.**
   - 03's hourly roll-up source (9.1, Q-055);
   - 03's export list against its import sentence (9.2, Q-056);
   - 02, 09 and 14 naming the update badge's places differently (9.4, Q-058);
   - O-17's "reset first" when `Reset all settings…` never touches the database (9.2).
5. **Process noise.**
   - **Postmortem commit counts:** headers were fixed by a follow-up commit, which changed the count again; 9.2–9.4 each spent one commit on it.
   - **Refused removals:** the harness refused `rm` with an unguarded variable or inside `bash -c` (9.3); scratch files now stay in the session scratchpad.
   - **Cancelled CI:** main's push run for 9.4 (e2a4465, run 44299406950) was cancelled on attempt 1 with no failing step, and attempt 2 passed. stage-9.4.md doesn't record it, since no commits go to main after a merge (§ 0.6).

## Plan and doc changes
- **03:**
  - the retention table, as built (harness keeps `harness` when rolled up, anchor days stay hourly, first and last balance snapshots, monthly rows skipped by readers; 9.1);
  - § Durability: what an import reproduces, the key hint, the CSV shape (9.2).
- **07:** `sched.clock_jump`'s `reason` gains `timezone` (9.5).
- **14:** stages 9.1–9.5's Inventory and Tests lines name the files and cases built.
- **Scripts:**
  - `check-log-events.sh --from-tests` (9.5);
  - 1.3.sh's "not yet" guards are all retired (PM-8.3-1);
  - 4.3.sh's daily order check includes `roll-ups` and `update check` (PM-4.3-3).
- **Correction in 9.1:** phase-8.md's pattern 4, and Q-054's audit tolerance (PM-8.4-2 widened).
- **Proposed for later:** none beyond the carry-forwards below.

## Gates and risks
- **H2 (OpenAI) and H3 (DeepSeek, xAI) recordings:** open (owner). `Verified` is empty, so a Release build offers no provider at onboarding.
- **H5 (SOAK-1), starts now:** 14 days on the owner's Mac with real keys, log level `info`. Pass: zero `fault`, and every `error` has a `QUESTIONS.md` entry or a fix.
  - **Which build:** a Debug build launched without a test root. Release offers no provider until H2/H3 close. The owner launches it, never the agent (D10).
  - **Conflict with the verifies:** UI tests launch `dev.bathyon.tokenbe` through XCUITest, and 2.1.sh, 0.4.sh, 4.1.sh and 9.5.sh quit `TokenBe` by name. Either would stop a soak instance on this Mac. A stopped instance logs `crash.previous_launch` (fault) at its next launch and fails SOAK-1.
  - **Owner decision, asked when this phase merged:** how the soak and the remaining verifies share the Mac.
- **Risks for phase 10:**
  - The Anthropic and OpenRouter adapters run on synthetic fixtures only (gated, hidden in Release).
  - Coverage sits at 97.1 %: each adapter needs its failure branches tested.
  - UI runs must not stop the soak (above).

## Open carry-forward actions
- **Phase 9:**
  - PM-9.1-1 · agent · 11.1 · LOAD-1 on `rollupMonthly`'s full read.
  - PM-9.2-1 · agent · 11.2 · `provider_key.redacted` stores the provider's value (SEC-1 will match `sk-FIXTURE`).
  - PM-9.3-1 · agent · 11.3 · 04's decode badge.
  - PM-9.4-1 · agent · 11.5 · the first `update.check_ok` after the first release; until then, a daily 404 warn.
  - PM-9.5-1 · Nikola · 11.5 · the H5 soak.
  - PM-9.3-2 · agent · every stage · process (the pre-verify routine).
- **Phase 8:**
  - PM-8.1-1 (the H2 PR);
  - PM-8.1-2 (10.1);
  - PM-8.4-1 (Nikola, 11.3);
  - PM-8.4-2 (11.3);
  - process: PM-8.2-3, PM-8.2-5, PM-8.3-2, PM-8.4-3.
- **Phase 7 and earlier:**
  - PM-7.1-4 (11.3);
  - PM-7.1-5 (11.5);
  - PM-7.2-3 (10.2);
  - PM-7.3-4 (11.3);
  - PM-6.1-1 and PM-6.2-1 (the H3 PR);
  - PM-5.2-3 (accepted);
  - PM-5.4-2 (11.5, re-targeted in 9.5);
  - process: PM-7.1-6, PM-7.1-7, PM-7.2-4, PM-7.2-5, PM-7.3-1, PM-7.3-2.
