# Stage 3.6 — Verify OpenAI against the live API (H2) (14 § Stage 3.6). Sourced by scripts/verify-stage.sh.
# H2 blocks only the Verified flip (14 § 0.4), and a stage may merge with its gate open (14 § 0.6 rule 4). Until the
# owner's recording lands (`openai/RECORDED`), the gate checks print `skip` and openai must stay out of Verified.
# The PR that consumes H2 makes them unconditional (Q-033, PM-3.6-2).

fx=Tests/Fixtures/providers/openai
oa=Sources/TokenBeCore/Providers/OpenAI
rec=scripts/record-fixtures.sh
inventory=(Sources/TokenBeCore/Providers/Verified.swift docs/02-provider-apis.md $rec scripts/stages/3.6.sh)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# The recorder, ready for the row-bearing re-record (Q-032): pages to the end, anonymizes people, records the 401.
check "recorder follows next_page for usage and costs" bash -c "grep -qF 'fetch_pages openai usage_completions' $rec && grep -qF 'fetch_pages openai costs' $rec"
check "recorder rewrites next_page to the next case (Q-029)" grep -qF 'body["next_page"] = next_case' $rec
for literal in 'key_fixture_' 'user_fixture' 'owner@example.invalid' 'Fixture Owner'; do
  check "recorder anonymizes: $literal" grep -qF "$literal" $rec
done
check "recorder records the real 401 body (PM-3.4-2)" grep -qF 'KEY_VALUE="sk-admin-""TOKENBEFIXTUREINVALID0000"' $rec
check "recorder self-test (offline, fake keys)" $rec --self-test

# Envelope keys confirmed by the first recording: in 02 and declared in the DTOs, so they never log poll.unknown_keys.
check "02 has the recorded list and project envelope" grep -qF 'Recorded 2026-11-12: `{ "object":"list"' docs/02-provider-apis.md
check "02 has the bucket *_iso fields" grep -qF '"start_time_iso":string, "end_time_iso":string' docs/02-provider-apis.md
for literal in 'case firstID = "first_id"' 'case hasMore = "has_more"' 'case archivedAt = "archived_at"' \
               'case startTimeISO = "start_time_iso"' 'case endTimeISO = "end_time_iso"'; do
  check "DTOs declare $literal" grep -qF "$literal" $oa/DTOs.swift
done
check "fixtures pass record-fixtures.sh --verify-redacted (R11)" $rec --verify-redacted
check "check-no-secrets.sh" scripts/check-no-secrets.sh

# The gate (H2): recorded fixtures, openai in Verified, no openai [expected] left in 02.
openai_expected() { awk '/^## openai/,/^## anthropic/' docs/02-provider-apis.md | grep -c '\[expected\]'; }
if [[ -e $fx/RECORDED ]]; then
  check "RECORDED's first line is a date" bash -c "head -n 1 $fx/RECORDED | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\$'"
  for name in projects.ok api_keys.ok usage_completions.ok costs.ok projects.401; do
    check "recorded fixture $name" test -s "$fx/$name.recorded.json"
  done
  check "openai is in Verified" grep -qF '.openai' Sources/TokenBeCore/Providers/Verified.swift
  check "no [expected] left in 02 § openai" test "$(openai_expected)" -eq 0
else
  echo "skip ${STAGE} recorded fixtures, Verified flip, 02 § openai [expected] = 0 (H2 open: no $fx/RECORDED)"
  check "openai stays out of Verified while H2 is open (R13)" grep -qF 'public static let providers: Set<ProviderID> = []' Sources/TokenBeCore/Providers/Verified.swift
fi

for suite in VerifiedProvidersTests OpenAITests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
