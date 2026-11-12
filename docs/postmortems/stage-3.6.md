# Postmortem — Stage 3.6 Verify OpenAI against the live API (H2)
Date: 2026-11-12 · Branch: s3.6-openai-verify · PR: #17 · Planned size: S · Commits: 4

## Outcome
OpenAI is ready to be verified, but is **not verified yet**. H2 is open: the stage merges with its gate open (14 § 0.6 rule 4, Q-033), and the owner asked to move on to 4.1 while the gate waits.
- **The owner's first recording** (2026-11-12) succeeded but came from an org with no activity: no project keys, and empty `results[]` in every usage and cost bucket. It confirmed the envelopes only, so 02's row fields keep `[expected]` and openai stays out of `Verified` (Q-032). The empty files stay outside the repository.
- **The recorder is ready for the re-record** (433da27):
  - it follows `next_page` to the last page, at most 8, rewriting each page's token to the next fixture case;
  - it anonymizes key ids, user ids, emails and owners' names, since the repository is public;
  - it records the real 401 body (PM-3.4-2).
- **Confirmed now** (4e42b3e): the list envelope (`object`, `first_id`, `last_id`, `has_more`), the project fields, and the bucket `start_time_iso`/`end_time_iso` are in 02 and declared in the DTOs, so they never log `poll.unknown_keys`. A test decodes the recorded shapes.
- **What the user sees:** nothing new. Debug builds offer OpenAI as in 3.5. Release builds still offer no provider (D-verified-providers).

DoD:
- D2, D3 (no new failure path), D9 (02, Q-032, Q-033) and D11 are met; D12 comes from this PR's CI.
- D1 is partly met. The inventory's `openai/*.recorded.json` and `openai/RECORDED` arrive with the gate (PM-3.6-2).
- 14's Verify line (`VerifiedProvidersTests`; zero openai `[expected]`) and steps 2–3 (the field diff, `Verified`, the Debug run with the owner) move to the PR that consumes H2. Until then, `3.6.sh` prints them as one `skip` line.

## What went as planned
- The recorder's changes were tested offline first: `--self-test` redacts a canned body with fake keys, a person object and a key id, and the anonymized output passes `--verify-redacted`. No key was used by the agent at any point (CLAUDE.md, R13).
- The envelope keys went into 02 and the DTOs in the same commit, with a test (PM-3.4-2).
- The new stage script's static checks were sourced on their own before any verify (PM-1.3-5). That dry run caught the key-shaped literal below in seconds.

## What went wrong
1. **The first recording had no rows.**
   - **Root cause:** the org had never made a request, so there were no project keys and no usage or cost results. Nothing in 14 or the recorder said that H2 needs an org with activity.
   - **Fix:** Q-032 B. The owner creates a key named `tokenbe-fixture`, makes three tiny requests, waits about an hour, then re-records (PM-3.6-1).
   - **Cost:** one owner round trip, and the gate stays open.
2. **The recorder could not have recorded a full window.** It fetched only page 1, but both endpoints page (24 hourly buckets per page), so today's activity would have been on a page never fetched. The live `next_page` token (`page_AAAA…=`) is also not a valid fixture case. **Fix:** `fetch_pages` and the token rewrite (433da27, Q-032). It was found by reading the empty recording, before the re-record, so no recording was wasted.
3. **Personal data in recordings.** Real API-key rows carry the owner's name and email, and the repository is public. **Fix:** the recorder anonymizes them (433da27), and the self-test asserts it.
4. **A key-shaped literal was committed.** 433da27 put the invalid test key `sk-admin-…0000` in the recorder, and Q-032 quoted it in full. `check-no-secrets.sh` flags both, so 3.4's and 3.6's checks would have failed.
   - **Root cause:** the literal matched the 07 key pattern. The same class of problem as 3.3's Release-binary finding.
   - **Fix:** the script joins the literal from two parts, and Q-032 names the parts instead.
   - **Cost:** none. The 3.6 dry run caught it before any verify.

## Verify and CI failures
- Static dry run of `3.6.sh`: `check-no-secrets.sh` failed on the literal above (What went wrong 4); fixed before the first verify.
- Verify run 1 (`TB_UI_TESTS=0`): every stage check of 0.1–3.6 green; D13 failed only on the missing `stage-3.6.md`, as expected before this file existed.

## Deviations from the docs
- **14 § Stage 3.6:** steps 2–3 and the Verify line move to the PR that consumes H2. `3.6.sh` asserts the present state, and its gate checks wait for `openai/RECORDED` (Q-033, PM-3.6-2).
- **02 § openai:** the recorded list/project envelope and the bucket `*_iso` fields are added; `bucket_width=1h` paging and the `next_page` token format are noted (4e42b3e, Q-032).
- **No change to 11:** which synthetic fixtures stay (429, 500, 403) is decided when the recordings arrive.

## Judgment calls
- Q-032: the empty recording; paging, anonymizing and the 401 body in the recorder.
- Q-033: merge 3.6 with H2 open; gate checks keyed on `RECORDED`.

## Carry-forward actions
- PM-3.6-1 · Nikola · H2 · Re-record:
  1. Create a project key named `tokenbe-fixture`.
  2. Make three tiny requests with it.
  3. Wait about an hour.
  4. In your own Terminal, run `set -a; . ./.env; set +a; scripts/record-fixtures.sh openai; unset OPENAI_ADMIN_KEY`.

  Status: open.
- PM-3.6-2 · agent · the PR that consumes H2 · Steps, in order:
  1. Run the redaction grep over the new files.
  2. Diff recorded against synthetic, field by field.
  3. In 02, remove each confirmed `[expected]` and correct any wrong field. Also check the real error-body shape and the `redacted_value` format (the rest of PM-3.4-2).
  4. Add `.openai` to `Verified`.
  5. Delete the synthetic files that have recorded counterparts. Keep 429, 500 and 403, and label them in 11.
  6. Make `3.6.sh`'s gate checks unconditional, and change `3.4.sh`'s "no RECORDED marker" and "empty Verified" checks.
  7. Do the Debug run against the live key with the owner (14 step 3).
  8. Append `## Addendum — H2 closed <date>` to this file.

  Status: open.
- PM-3.6-3 · agent · 4.1 · The coordinator polls a new account at once, so onboarding's `Done` no longer runs its own `keys`/`usage` polls. Update `3.5.sh`'s "Done runs the first keys and usage polls" check in the same PR. Status: open.
- Earlier actions that targeted 3.6:
  - PM-3.1-2: closed in 3.3 (the recorder writes the envelope).
  - PM-3.4-2: partly closed. The confirmed envelope keys are in 02 and the DTOs (4e42b3e), and the recorder records the 401 body (433da27). The error-body shape and `redacted_value` are re-targeted → PM-3.6-2 (they need the row-bearing recording).
