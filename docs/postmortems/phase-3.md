# Postmortem — Phase 3 Accounts (OpenAI)
Date: 2026-11-12 · Stages: 3.1 (#11), 3.2 (#12), 3.3 (#13), 3.4 (#14), 3.5 (#15), 3.6 (#17); process PR #16 (Q-031)

## Outcome vs. phase map
14 § 0.5: "User adds an OpenAI account; keys discovered; one-shot polls write buckets."
- **User adds an OpenAI account:** met in Debug builds (3.5): onboarding, Keychain storage (3.2), Settings → Accounts. Release builds offer OpenAI only after H2, because a provider must be in `Verified` before a Release build offers it (D-verified-providers, R13). That waits on PM-3.6-1.
- **Keys discovered:** met. Probe step 2 and the `keys` job upsert `provider_key` rows (3.4), and the Accounts tab lists them under Keys & apps (3.5).
- **One-shot polls write buckets:** met on synthetic fixtures. Onboarding's `Done` runs the first `keys` and `usage` polls, and the adapter tests assert exact rows, paging, resume, retries and the circuit (3.4).
  - Against the live API, only the envelopes are confirmed (3.6, Q-032). The row fields stay `[expected]` until the row-bearing re-record.
- **Seams in place:** network (3.1), keychain (3.2), provider (3.3), each with its production and test implementations (14 § 0.3).

## Patterns across stages
1. **Key-shaped literals keep tripping the secret guard.**
   - **Where:** 3.3 (prefixes packed together in the Release binary) and 3.6 (an invalid test key in the recorder and in Q-032).
   - **Root cause:** test and tooling code needs strings shaped like keys, and the 07 pattern is deliberately broad.
   - **Effect:** the guard did its job both times.
   - **Durable rule:** build such strings from parts at run time (Q-028), and run `check-no-secrets.sh` right after writing any key-like literal, not only after a Release build (PM-3.3-4, widened).
2. **External preconditions found late.**
   - **Where:**
     - 3.2: the data-protection keychain needs a provisioned build;
     - 3.4: the no-network guard was keyed on the local runner;
     - 3.6: H2 needs an org with activity.
   - **Root cause:** each time, the plan assumed something about the environment (signing, CI runner, provider account state) without a step that checks it.
   - **What worked:** a spike first (PM-1.3-1, PM-3.2-4), then asking the owner once with concrete options.
3. **Later stages break earlier stage scripts.**
   - **Where:** 3.4 (`3.2.sh`'s "next N lines" xunit check) and 3.5 (several earlier checks and tests).
   - **Cost:** a full verify run each time.
   - **What helps:** dry-running the later scripts and grepping `scripts/stages/*.sh` for every symbol a stage changes (PM-3.4-6, PM-3.5-5). 3.6 followed this and lost no verify run.
4. **First-lint and first-test churn on large stages** (3.1, 3.3, 3.4). Lint after each slice (PM-3.4-5) made 3.5 and 3.6 clean on their first lint.

## Plan and doc changes
- **Applied during the phase:**
  - 13, 11 and 14: the login keychain instead of the data-protection keychain (Q-027, 3.2).
  - 14 § 0 and `verify-stage.sh`: UI tests run at phase end, and on stages that touch the app or the UI tests (Q-031, #16).
  - 02 § openai: the recorded envelope and the paging notes (3.6, Q-032).
  - Q-026 to Q-033 logged.
- **Applied in this PR:**
  - PM-3.5-4 is re-targeted from "3.7" to 10.1. 14 has no stage 3.7; the Anthropic adapter is 10.1. Q-030 and the 3.3 and 3.5 postmortems are corrected.
- **Proposed for later phases:**
  - **4.1:** it changes 3.5's behaviour. The coordinator polls a new account at once, so onboarding's `Done` no longer needs its own `keys`/`usage` calls. `3.5.sh`'s "Done runs the first keys and usage polls" check must follow in the same PR (PM-3.6-3).
  - **The PR that consumes H2:** it updates `3.4.sh` and `3.6.sh` (PM-3.6-2).

## Gates and risks
- **H2 is open** (PM-3.6-1, owner). Phases 4–5 proceed on synthetic fixtures (14 § 0.4). When the recording lands, PM-3.6-2 closes it in its own PR, and `stage-3.6.md` gets the addendum.
- **H3–H5:** not due yet.
- **Risks for Phase 4 (Scheduling):**
  - **Polling becomes continuous.** 4.1 is the first stage where the app sends requests without a user action. Fixture mode and the test root must keep every verification launch off the network (D10, PM-3.4-9). The 3-minute cadence check runs in fixture mode only.
  - **Timing tests.** The scheduler is the first heavy user of `TestClock` across actors. Every async test waits on conditions, never on a yield count, and the 50-run loop applies (PM-1.2-3).
  - **The OpenAI shapes may still change.** If the H2 recording corrects a row field, the DTOs change under a running scheduler. The adapter tests catch the shape, and the scheduler only needs `Poller.Outcome`.

## Open carry-forward actions
- **Phase 3:**
  - PM-3.6-1 · Nikola · H2 · Re-record OpenAI with an active org.
  - PM-3.6-2 · agent · the PR that consumes H2 · Verified flip, diff, `[expected]`, synthetic cleanup, `3.4.sh`/`3.6.sh`, the Debug run, the addendum.
  - PM-3.6-3 · agent · 4.1 · Onboarding's `Done` defers to the coordinator; update `3.5.sh` in the same PR.
  - PM-3.1-4 · agent · 4.1 · `ManualNetworkMonitor`, the `NWPathMonitorAdapter` wiring, `sched.skip reason=offline`.
  - PM-3.5-3 · agent · 4.1 · The scheduler consumes `account.paused`; `SummaryInputs` carries it.
  - PM-2.2-3 · agent · 4.1–5.3 · Grow `SummaryInputs` per stage, with an observation test per added table.
  - PM-3.4-8 · agent · 4.2 · Find what wrote `tb.ui.dashboardRange = 7d`; make `1.2.sh` independent of later suites.
  - PM-3.4-3 · agent · 5.x pricing · Reprice provider rows (`price.repriced`).
  - PM-3.4-4 · agent · 6.1 · `Repository+Balance` and the poller's balance write.
  - PM-3.5-4 · agent · 10.1 · Anthropic's wrong-prefix copy.
  - PM-3.2-3 · agent · 11.2 · Re-assess Q-027 once Developer ID signing exists.
  - PM-1.1-3 · agent · 11.2 (re-targeted in 3.5).
  - Process: PM-3.1-5, PM-3.2-4, PM-3.3-3, PM-3.3-4, PM-3.4-5, PM-3.4-7, PM-3.4-9, PM-3.5-1, PM-3.5-2, PM-3.5-5.
- **Phase 2's open actions:** PM-2.2-1, PM-2.2-2, PM-2.2-4, PM-2.1-1/2 (process); PM-2.1-4 (9.x).
- **Phase 1's open actions:**
  - process: PM-1.3-1, PM-1.3-2, PM-1.2-1/2/3/5, PM-1.1-1;
  - PM-1.3-3 (5.5);
  - PM-1.3-4 (8.4 / 11.4);
  - PM-1.2-4 (9.5).
- **Phase 0's open actions:**
  - PM-0.1-3 (11.5);
  - PM-0.2-3 (9.5);
  - process: PM-0.3-2, PM-0.4-2, PM-0.5-1;
  - PM-0.4-3 (owner, `.env` permissions);
  - PM-0.5-2 (owner, coverage, 11.2).
