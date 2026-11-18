# 02 — Provider APIs (verified 2026-11-09)

RULE: Field names marked **[expected]** were taken from documentation or SDK sources and must be confirmed against a recorded fixture in Milestone 0 (`10 § Milestones`). If a fixture disagrees with this file, UPDATE THIS FILE in the same PR and make the adapter match the fixture. Never code to a field name that is neither here nor in a fixture.

RULE: Every adapter sends `User-Agent: TokenBe/<version> (+https://github.com/nbencic/tokenbe)`.

RULE: Every adapter stores the raw response body of the LAST successful call per endpoint in `poll_state.last_raw` (truncated to 64 KB, keys redacted) for diagnostics.

## Capability matrix

| Provider | Key type pasted | usage | cost | balance | perKey | keyNames | balance_mode default | usageLag | cost granularity |
|---|---|---|---|---|---|---|---|---|---|
| openai | Admin key `sk-admin-…` (Org Owner creates) | yes | yes | **no** | yes | yes | anchored | treat 1m/1h buckets < 60 min old as provisional; no published finalization window | 1d only |
| anthropic | Admin key `sk-ant-admin01-…` (needs an Organization; unavailable for individual accounts) | yes | yes | **no** | yes (usage only) | yes | anchored | ~5 min typical | 1d only |
| openrouter | Management key (Provisioning key) | $ per key only | $ per key only | yes | yes ($) | yes | direct | seconds | n/a |
| deepseek | Standard key | **no** | **no** | yes | **no** | no | direct | seconds–minutes | n/a |
| xai | Management key (console.x.ai → Settings → Management Keys; Q-062) | no | yes [expected] (USD per day per model, `/usage`) | not yet (prepaid balance unrecorded, H6) | no | no | anchored | ~1 h assumed (unpublished) | 1d |
| moonshot | Standard key (platform.kimi.ai, or platform.kimi.com for China; Q-062) | **no** | **no** | yes [expected] | **no** | no | direct | "may lag" (read as 5 min) | n/a |
| novita | Standard key (novita.ai → Settings → Key Management; Q-062) | **no** | not used in V1 | yes [expected] | **no** | no | direct | none published (read as 5 min) | n/a |

`balance_mode` values: `direct`, `anchored`, `spend_only`. `anchored` requires an anchor; until one exists the account behaves as `spend_only` and the UI shows "no runway until anchored".

## openai

Base: `https://api.openai.com`. Header: `Authorization: Bearer <admin key>`. Content-Type JSON.

### Probe (onboarding "Test connection")
1. `GET /v1/organization/projects?limit=100` → 200 proves admin scope. Store project ids and names.
   Recorded 2026-11-12: `{ "object":"list", "data":[…], "first_id", "last_id", "has_more":bool }`; each project has `object:"organization.project"`, `id`, `name`, `created_at`, `archived_at` (null), `status` (`active`), `residency` (`GLOBAL`), `psp_decryption_key_id` (null). The api_keys list has the same envelope.
2. For each project: `GET /v1/organization/projects/{project_id}/api_keys?limit=100` → `data[]` with `id`, `name`, `redacted_value`, `created_at`, `last_used_at` [expected]. Upsert into `provider_key` (provider_key_id = `id`).
3. `GET /v1/organization/usage/completions?start_time=<now-3600>&bucket_width=1h&limit=1` → 200 proves usage scope.
4. `GET /v1/organization/costs?start_time=<now-86400>&limit=1` → 200 proves cost scope.
A 401/403 on step 1, 3 or 4 sets the corresponding capability false and surfaces the exact HTTP body (redacted) in the probe result.

### Usage
`GET /v1/organization/usage/completions`
Query: `start_time` (unix seconds, inclusive, REQUIRED), `end_time` (unix seconds, exclusive), `bucket_width` ∈ `1m|1h|1d` (default `1d`), `limit` (buckets per page), `page` (cursor), `project_ids[]`, `user_ids[]`, `api_key_ids[]`, `models[]`, `group_by[]` ∈ `project_id|user_id|api_key_id|model|batch|service_tier`.
TokenBe calls with `bucket_width=1h`, `group_by[]=api_key_id&group_by[]=model&group_by[]=service_tier`, window = last 48 h, paging until no `next_page`.
Response: `{ "object":"page", "data":[ { "object":"bucket", "start_time":int, "end_time":int, "start_time_iso":string, "end_time_iso":string, "results":[ {…} ] } ], "has_more":bool, "next_page":string|null }`.
Recorded 2026-11-12 (envelope confirmed): `*_iso` are RFC 3339 UTC (`2026-11-10T11:00:00+00:00`), informational only. `bucket_width=1h` without `limit` returns 24 buckets per page, so the 48 h window takes 2–3 pages. `next_page` is an opaque token such as `page_AAAA…=` (base64 alphabet, contains `-` and `=`) and is percent-encoded in the next query.
Result fields [expected]: `input_tokens` (INCLUDES cached), `input_cached_tokens`, `input_cache_write_tokens` (may be absent → 0), `output_tokens`, `input_audio_tokens`, `output_audio_tokens`, `num_model_requests`, `project_id`, `user_id`, `api_key_id`, `model`, `batch` (bool), `service_tier`.
Known quirk: community reports of `input_cached_tokens` being 0 in the usage API while per-response usage reports cached tokens. Treat usage-API cache counts as LOWER BOUNDS; never compute cache savings from them for OpenAI (`05 § Cache savings`).
Reasoning tokens are not broken out in this endpoint → `reasoning = 0`.

### Cost
`GET /v1/organization/costs`
Query: `start_time` (REQUIRED), `end_time`, `bucket_width` = `1d` ONLY, `limit` 1–180 (default 7), `page`, `project_ids[]`, `api_key_ids[]`, `line_items[]`, `group_by[]` ∈ `project_id|user_id|line_item|api_key_id|api_source`.
TokenBe calls daily with `group_by[]=api_key_id&group_by[]=line_item`, window = last 7 days (re-fetching finalizes provisional days).
Recorded 2026-11-12 (envelope confirmed): the same page and bucket shape as Usage, `*_iso` included; without `limit` a page holds 7 daily buckets, so the 7-day window takes 2 pages.
Result fields [expected]: `object:"organization.costs.result"`, `amount:{ "value":number, "currency":"usd" }`, `line_item`, `project_id`, `api_key_id`, `api_source`.
OpenAI states the Costs endpoint reconciles to the invoice; the Usage endpoint may not. Cost is TRUTH; usage × price is ESTIMATE.

### Balance
None. Community confirms no endpoint exists (Sept 2026). Account is `anchored`.

### Errors
401 invalid key; 403 missing scope; 429 → honor `Retry-After`; 5xx → retry policy (`04`). A key that is not an admin key returns 401 on `/v1/organization/*`: probe message = "This is not an Admin key. Create one at platform.openai.com → Settings → Organization → Admin keys (Organization Owner only)."

## anthropic

Base: `https://api.anthropic.com`. Headers: `x-api-key: <admin key>`, `anthropic-version: 2023-06-01`. (Docs also show `2026-10-21`; use `2023-06-01` until a fixture proves a newer version is required.)

### Probe
1. `GET /v1/organizations/me` → org id and name [expected fields: `id`, `name`]. 401 on an individual account (no organization) → probe message = "Admin API needs an organization. Console → Settings → Organization."
2. `GET /v1/organizations/api_keys?limit=100&status=active` → `data[]` with `id`, `name`, `workspace_id`, `partial_key_hint`, `status`, `created_at` [expected]. Upsert `provider_key`.
3. `GET /v1/organizations/workspaces?limit=100` → workspace ids/names [expected `id`, `name`].
4. `GET /v1/organizations/usage_report/messages?starting_at=<now-1h RFC3339>&bucket_width=1h&limit=1` → 200.
5. `GET /v1/organizations/cost_report?starting_at=<today 00:00Z>&limit=1` → 200.

### Usage
`GET /v1/organizations/usage_report/messages`
Query: `starting_at` (RFC3339 UTC, REQUIRED), `ending_at`, `bucket_width` ∈ `1m|1h|1d`, `limit` (1m: default 60 / max 1440; 1h: 24 / 168; 1d: 7 / 31), `page`, `group_by[]` ∈ `api_key_id|workspace_id|model|service_tier|context_window|inference_geo` (`speed` requires beta header — DO NOT USE), filters `api_key_ids[]`, `workspace_ids[]`, `models[]`, `service_tiers[]`, `context_window[]`.
TokenBe calls with `bucket_width=1h&limit=48&group_by[]=api_key_id&group_by[]=model&group_by[]=service_tier`, window = last 48 h.
Response: `{ "data":[ { "starting_at":RFC3339, "ending_at":RFC3339, "results":[ {…} ] } ], "has_more":bool, "next_page":string|null }`.
Result fields [expected]: `uncached_input_tokens`, `cache_creation: { "ephemeral_1h_input_tokens":int, "ephemeral_5m_input_tokens":int }`, `cache_read_input_tokens`, `output_tokens`, `server_tool_use: { "web_search_requests":int }`, `api_key_id`, `workspace_id`, `model`, `service_tier` (`standard|priority|batch`), `context_window` (`0-200k|200k-1M`).
Freshness: documented "typically within 5 minutes". Sustained polling once per minute is explicitly supported.

### Cost
`GET /v1/organizations/cost_report`
Query: `starting_at` (REQUIRED), `ending_at`, `bucket_width` = `1d` ONLY, `limit` (default 7, max 31), `page`, `group_by[]` ∈ `workspace_id|description`.
TokenBe calls daily with `group_by[]=workspace_id&group_by[]=description`, window = last 7 days.
Result fields [expected]: `currency` (`"USD"`), `amount` (decimal STRING in cents, e.g. `"12345.67"`), `workspace_id`, `description`, `cost_type`, `context_window`, `model`, `service_tier`, `token_type`.
Exclusions: Priority Tier costs are NOT in the cost report (track via usage `service_tier=priority`). Code execution costs appear under description `Code Execution Usage` and are not in the usage report. Per-key cost does NOT exist → per-key $ for Anthropic is always `≈`.

### Balance
None. GitHub issue anthropics/claude-code#47574 (Apr 2026) and a Sept 2026 follow-up confirm no public balance endpoint. Account is `anchored`.
Hard-stop signal: HTTP 400 `invalid_request_error` with message starting "Your credit balance is too low". Not 402.

## openrouter

Base: `https://openrouter.ai/api/v1`. Header: `Authorization: Bearer <management key>`.

### Probe
1. `GET /key` → `data` for the calling key; `is_management_key` or `is_provisioning_key` must be true [expected], else probe message = "This is a regular inference key. Create a Management key at openrouter.ai → Settings → Management keys."
2. `GET /credits` → `data.total_credits` (number, USD), `data.total_usage` (number, USD). Remaining = `total_credits − total_usage`.
3. `GET /keys?include_disabled=false&offset=0` → `data[]` with `hash`, `name`, `label`, `disabled`, `limit` (number|null), `limit_remaining` (number|null), `limit_reset` (`daily|weekly|monthly|null`), `usage`, `usage_daily`, `usage_weekly`, `usage_monthly`, `byok_usage*`, `created_at`, `updated_at`, `workspace_id` [expected]. Page with `offset` in steps of 100 until a page returns < 100.

### Balance + per-key spend (one poll, every 60 s)
`GET /credits` and `GET /keys`. Store `balance_snapshot` and per-key `usage_*` as `cost_bucket` rows with `group_key = hash`, `day = today`, `amount_cents = round(usage_daily × 100)`. OpenRouter gives dollars per key, NOT tokens or models → per-key rows have `model = '*'` and token classes = 0.
`/generation?id=` (per-request cost) and `/activity` (daily by model) are NOT used in V1.

## deepseek

Base: `https://api.deepseek.com`. Header: `Authorization: Bearer <key>`.

### Probe + balance (every 60 s)
`GET /user/balance` → `{ "is_available": bool, "balance_infos": [ { "currency": "CNY"|"USD", "total_balance": "110.00", "granted_balance": "10.00", "topped_up_balance": "100.00" } ] }`. Amounts are STRINGS. Store one `balance_snapshot` per currency entry; the account's display currency is the first entry's currency.
No usage, cost, or per-key endpoints exist. The only per-key breakdown DeepSeek offers is a manual dashboard ZIP export (not used). Per-app attribution for DeepSeek comes ONLY from harness reports (`06`).
Per-response usage fields the harness will copy verbatim: `prompt_tokens`, `completion_tokens`, `prompt_cache_hit_tokens`, `prompt_cache_miss_tokens`, `completion_tokens_details.reasoning_tokens` (reasoner models only), `total_tokens`.

## xai

Recorded 2026-11-18 by the soak (an inference key): `GET https://api.x.ai/v1/api-key` returns key metadata only (`acls`, `api_key_blocked`, `api_key_disabled`, `api_key_id`, `create_time`, `modified_by`, `modify_time`, `name`, `redacted_api_key`, `team_blocked`, `team_id`, `user_id`) and no balance. TokenBe no longer calls it (Q-062).

Base: `https://management-api.x.ai`. Header: `Authorization: Bearer <management key>`. A management key is separate from inference keys (console.x.ai → Settings → Management Keys). It can also buy credit and change limits and billing details; TokenBe calls ONLY the paths below (10.0.2.sh fails on any other management path). Fields are from xAI's Management API reference (docs.x.ai → REST API reference → Management → Accounts and Authorization, Billing) and are **[expected]** until H6 records them.

### Probe
1. `GET /auth/management-keys/validation` → `{ apiKeyId, teamId (deprecated), scope ("SCOPE_TEAM"|"SCOPE_ORGANIZATION"|"SCOPE_UNSPECIFIED"), scopeId, ownerUserId, createTime, modifyTime, name, acls[], apiKey, redactedApiKey, ipRanges }` (the docs' example spells `reactedApiKey`). The team is `scopeId` when `scope == "SCOPE_TEAM"`, else `teamId`. Neither → message `This management key is not tied to a team. Create a team management key at console.x.ai → Settings → Management Keys.`
2. `POST /v1/billing/teams/{team_id}/usage` over the last day (the cost request below) → 200 proves billing read access.
- 401/403 at either step → `xAI did not accept this management key. Create one at console.x.ai → Settings → Management Keys and paste it.`
- Result: `capabilities.cost = true`, `balance = false`, mode `anchored` (onboarding asks for an anchor), currency USD.

### Cost (every `tb.poll.keysIntervalS`; also in the daily activity)
`POST /v1/billing/teams/{team_id}/usage`, body `{"analyticsRequest": {"timeRange": {"startTime": "YYYY-MM-DD 00:00:00", "endTime": "YYYY-MM-DD 00:00:00", "timezone": "Etc/GMT"}, "timeUnit": "TIME_UNIT_DAY", "values": [{"name": "usd", "aggregation": "AGGREGATION_SUM"}], "groupBy": ["description"], "filters": []}}`; `endTime` is exclusive; the range is the 7-day cost lookback in whole UTC days through today. Response `{ "timeSeries": [ { "group": [string], "groupLabels": [string], "dataPoints": [ { "timestamp": "2025-10-01T00:00:00Z", "values": [number] } ] } ], "limitReached": bool }`; `values[0]` is US dollars (a JSON number). The team is re-read from step 1 on every poll (no new column).
- Rows: per UTC day, one `cost_bucket` per model (`group_kind = 'description'`, `group_key = group[0]`) and one `total`, dollars summed in `Decimal` and rounded to cents once, half up. A day whose end + 1 h is not yet past is provisional.
- `limitReached == true` → keep the rows, log `poll.provider_rule` `xai_usage_limit_reached` (warn, once a day).

### Balance (not called until H6)
`GET /v1/billing/teams/{team_id}/prepaid/balance` → `{ "changes": [ { teamId, changeOrigin ("PURCHASE"|"SPEND"|"REFUND"|"MANUAL"|"AUTO_PURCHASE"), topupStatus, amount {val}, invoiceId, invoiceNumber, createTime, paymentProcessor {kind} } ], "total": { "val": string } }`, USD cents. The docs' example after one purchase has `total.val = "-1000"` (purchases negative, spend positive), so `total` looks like a ledger sum whose negation is the remaining credit; unproven. When H6 records it, xAI may turn direct (`balance = true`).

Never called: `prepaid/top-up`, `postpaid/spending-limits`, `billing-info`, `payment-method`, `invoices`, `postpaid/invoice/preview`, and every other management path.

## moonshot

Hosts: `https://api.moonshot.ai` (international, amounts in **USD**) and `https://api.moonshot.cn` (China, amounts in **CNY**). Header: `Authorization: Bearer <key>`. A key works on its own region only; the other region answers 401. Fields are from Moonshot's balance page (platform.kimi.ai / platform.kimi.com → docs → API → balance) and are **[expected]** until H6 records them (Q-062).

### Probe + balance (every `tb.poll.balanceIntervalS`)
`GET /v1/users/me/balance` → `{ "code": 0, "data": { "available_balance": 49.58894, "voucher_balance": 46.58893, "cash_balance": 3.00001 }, "scode": "0x0", "status": true }`. Amounts are JSON NUMBERS in the region's currency; no currency field.
- `available_balance` = cash + voucher (when `cash_balance` < 0, it equals `voucher_balance`); `voucher_balance` ≥ 0; `cash_balance` < 0 means the account owes money.
- Probe: the international host first; a 401 there tries the China host (`poll.region_fallback`, debug). The host that answers sets the account currency (USD or CNY), and the balance poll derives its host from that currency (no new column).
- `status == false` or `code ≠ 0` → `poll.provider_rule` `moonshot_status_not_ok`; probe message: unexpected response.
- Refused on both hosts (or 403) → `Moonshot did not accept this API key. Check it at platform.kimi.ai (or platform.kimi.com for China) → API Keys and paste it again.`
- Snapshot: `amount_cents = available_balance`, `granted_cents = voucher_balance`, `topped_up_cents = cash_balance` (may be negative), each rounded to cents once, half up.
No usage, cost, or key-list endpoint exists (spend history is console only; the day's bill updates at 07:00 the next day). Per-app attribution comes ONLY from harness reports (`06`). Per-response usage is OpenAI-compatible (`prompt_tokens`, `completion_tokens`, `total_tokens`) [expected].

## novita

Base: `https://api.novita.ai`. Header: `Authorization: Bearer <key>` (the inference key). Fields are from Novita's API reference (docs.novita.ai → API reference → Basic → User Balance Info) and are **[expected]** until H6 records them (Q-062).

### Probe + balance (every `tb.poll.balanceIntervalS`)
`GET /openapi/v1/billing/balance/detail` (no parameters) → `{ "availableBalance": "1000000", "cashBalance": "800000", "creditLimit": "200000", "pendingCharges": "0", "outstandingInvoices": "0" }`. All amounts are STRINGS in **1/10000 USD** (`"10000"` = $1.00): `availableBalance` is what can be spent (it includes the credit limit), `cashBalance` the remaining top-up, `creditLimit` the most the account may owe, `outstandingInvoices` what it owes now, `pendingCharges` currently always 0.
- Snapshot: `amount_cents = availableBalance`, `topped_up_cents = cashBalance`, each ÷ 100 and rounded half away from zero (05 § Currency); currency USD.
- 401/403 → `Novita did not accept this API key. Check it at novita.ai → Settings → Key Management and paste it again.`
The per-key bill list (`GET /openapi/v1/billing/apikey/bill/list`) is NOT used in V1 (direct balance; per-app attribution comes from harness reports, `06`). Per-response usage is OpenAI-compatible (`prompt_tokens`, `completion_tokens`, `total_tokens`) [expected].

## Price feed

`GET https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` — community-maintained. Fields used: `input_cost_per_token`, `output_cost_per_token`, `cache_read_input_token_cost`, `cache_creation_input_token_cost`, `cache_creation_input_token_cost_above_1hr`, `input_cost_per_token_above_200k_tokens`, `output_cost_per_token_above_200k_tokens`, `cache_read_input_token_cost_above_200k_tokens`, `litellm_provider`, `mode`. All costs are USD per token. Lookup order is in `05 § Price lookup`. Fetch: once per day in the background activity (`04`), `If-None-Match` with stored ETag, 10 s timeout, body limit 20 MB, parse failure keeps the previous snapshot and logs `price.parse_failed`.

## Update check

`GET https://api.github.com/repos/nbencic/tokenbe/releases/latest` once per day in the background activity. Compare `tag_name` (semver, `v` prefix stripped) with the bundle version. Newer → Settings and Overview show "Update available" with the `html_url`. No download, no install.

## Definition of done for adapters
- Each adapter has a recorded fixture per endpoint under `Fixtures/<provider>/` (redacted) and a decode test.
- Each adapter's probe returns a `Capabilities` value and a human message for every failure class in this file.
- Each adapter logs `poll.<provider>` records per `07`.
- No adapter contains a field name that is absent from both this file and its fixture.
