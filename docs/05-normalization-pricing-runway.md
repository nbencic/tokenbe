# 05 — Normalization, pricing, runway, bands, drift

All arithmetic is integer cents (`Int64`) and integer tokens. Division happens once, at display time, using `Decimal`. Never `Double` for money.

## TokenClasses (the only usage shape the rest of the app sees)

```swift
struct TokenClasses: Sendable, Equatable {
  var inputUncached: Int64 = 0
  var cacheWrite5m:  Int64 = 0
  var cacheWrite1h:  Int64 = 0
  var cacheRead:     Int64 = 0
  var output:        Int64 = 0      // EXCLUDES reasoning when the provider reports reasoning separately
  var reasoning:     Int64 = 0
  var requests:      Int64 = 0
}
```

## Normalizers (exact rules)

| Provider / source | inputUncached | cacheWrite5m | cacheWrite1h | cacheRead | output | reasoning |
|---|---|---|---|---|---|---|
| openai usage API | `input_tokens − input_cached_tokens` (floor at 0; if negative log `normalize.negative`) | `input_cache_write_tokens ?? 0` | 0 | `input_cached_tokens` | `output_tokens` | 0 (not reported) |
| openai per-response (harness, chat.completions) | `prompt_tokens − prompt_tokens_details.cached_tokens` | 0 | 0 | `prompt_tokens_details.cached_tokens ?? 0` | `completion_tokens − completion_tokens_details.reasoning_tokens` | `completion_tokens_details.reasoning_tokens ?? 0` |
| openai per-response (harness, responses API) | `input_tokens − input_tokens_details.cached_tokens` | 0 | 0 | `input_tokens_details.cached_tokens ?? 0` | `output_tokens − output_tokens_details.reasoning_tokens` | `output_tokens_details.reasoning_tokens ?? 0` |
| anthropic usage API | `uncached_input_tokens` | `cache_creation.ephemeral_5m_input_tokens` | `cache_creation.ephemeral_1h_input_tokens` | `cache_read_input_tokens` | `output_tokens` | 0 (thinking is billed as output and included) |
| anthropic per-response (harness) | `input_tokens` (already uncached) | `cache_creation.ephemeral_5m_input_tokens ?? cache_creation_input_tokens ?? 0` | `cache_creation.ephemeral_1h_input_tokens ?? 0` | `cache_read_input_tokens ?? 0` | `output_tokens` | 0 |
| openrouter per-key | all 0 — OpenRouter per-key data is dollars only; `model='*'` | | | | | |
| deepseek per-response (harness) | `prompt_cache_miss_tokens ?? (prompt_tokens − prompt_cache_hit_tokens)` | 0 | 0 | `prompt_cache_hit_tokens ?? 0` | `completion_tokens − (completion_tokens_details.reasoning_tokens ?? 0)` | `completion_tokens_details.reasoning_tokens ?? 0` |
| xai per-response (harness) | `prompt_tokens − (prompt_tokens_details.cached_tokens ?? 0)` | 0 | 0 | `prompt_tokens_details.cached_tokens ?? 0` | `completion_tokens − (completion_tokens_details.reasoning_tokens ?? 0)` | `completion_tokens_details.reasoning_tokens ?? 0` |

Unknown keys in a usage object are collected and logged once per day per provider as `normalize.unknown_keys`. They never fail normalization. A missing REQUIRED key (`prompt_tokens`/`input_tokens`/`uncached_input_tokens`) fails normalization: the harness line is stored with `classes_json = NULL` and logged `normalize.failed`.

## Price lookup (deterministic order; first hit wins)

Given `provider` and `model` (string as reported by the provider):
1. `price_override[model]`
2. feed key `model` exactly
3. feed key `"{litellm_provider_prefix}/{model}"` where prefix is `openai` → none (OpenAI keys are bare), `anthropic` → none (bare), `deepseek` → `deepseek`, `xai` → `xai`, `openrouter` → `openrouter`
4. feed key with a trailing date suffix stripped (`-YYYYMMDD` or `-YYYY-MM-DD`) applied to 2 and 3
5. feed key with `-latest` appended applied to 2 and 3
6. UNPRICED → `nil`

Entries with `mode != "chat"` are ignored. A hit whose `input_cost_per_token` or `output_cost_per_token` is missing or ≤ 0 is treated as UNPRICED (invariant V5).

## Cost formula (per bucket, cents, round half-up once at the end)

```
cost = inputUncached × in
     + cacheWrite5m × (cache_creation_input_token_cost ?? in × 1.25)
     + cacheWrite1h × (cache_creation_input_token_cost_above_1hr ?? cache_creation_input_token_cost ?? in × 2.0)
     + cacheRead × (cache_read_input_token_cost ?? in × 0.1)
     + output × out
     + reasoning × out
```
`in`/`out` are the feed's USD-per-token values × 100 (cents). The `_above_200k_tokens` feed variants are NOT applied in V1: `usage_bucket` has no `context_window` grain (02 does not request that group_by; see 13 O-7). Long-context Anthropic requests are therefore priced at the base rate and this is one documented source of the `±` band (`drift` term).
Fallback multipliers (1.25, 2.0, 0.1) are used ONLY when the feed lacks the explicit field, and the bucket is logged `price.fallback_multiplier` once per model per day.
Service tier: `priority` and `batch` buckets are priced with the standard rate and flagged `tier_priced_as_standard` in the log; no tier multipliers in V1.

## Spend definitions (cents, per account)

- `spend_truth(day)` = Σ `cost_bucket.amount_cents` for that day (`group_kind='total'` row, which the adapter writes as the sum of its grouped rows).
- `spend_est(window)` = Σ `usage_bucket.est_cost_cents` for `source='provider'` rows in the window (plus `source='harness'` rows ONLY for accounts with `capabilities.usage = false`).
- `spend_since_anchor` = Σ `spend_truth(day)` for closed days after the anchor day + `spend_est` for the anchor day's remainder and today (open day). If an account has no cost capability, `spend_est` is used for all days.
- `unpriced_cents(window)` = Σ over unpriced buckets of `(inputUncached + cacheRead + cacheWrite + output + reasoning) × median_in_rate_of_priced_models_in_window`. Reported separately; never added to spend.

## Remaining

- `direct`: latest `balance_snapshot.amount_cents` (first currency entry). Band `±` = 0. Rendered without `≈`.
- `anchored`: `remaining = anchor.amount + Σ topups(after anchor) − spend_since_anchor`. Rendered `≈ $N ± M` with `N` rounded to whole units and `M` from § Estimate band.
- `spend_only`: no remaining, no runway; cards show today's and 30-day spend.

## Estimate band `M` (cents)

```
lag_days   = usageLag / 86400                       // provider lag (02)
drift      = spend_since_anchor × 0.03              // 3 % accounting tolerance
unreported = burn_7d × lag_days
unpriced   = unpriced_cents(since anchor)
age_factor = max(1, 1 + 0.5 × floor((now − anchor.ts) / anchor_age_days))   // anchor_age_days from 09, default 30
M          = (drift + unreported + unpriced) × age_factor
```
Display: `M` rounded UP to whole units; if `M ≥ remaining`, display `≈ $N ± N` and set band `unknown` (see Bands).

## Burn (cents per day)

- `burn_7d` = Σ spend over the last 7 CLOSED UTC days ÷ 7. If fewer than 2 closed days have data → `nil`.
- `burn_today` = `spend_est(today so far) × 86400 / seconds_since_utc_midnight`, only if `seconds_since_utc_midnight ≥ 7200` AND `spend_est(today) ≥ 100` cents; else `nil`.
- Display uses local calendar labels but computes on UTC days (provider cost buckets are UTC).

## Runway

```
runway_7d    = remaining / burn_7d        (nil if either nil or burn_7d == 0)
runway_today = remaining / burn_today     (nil if either nil)
runway_min   = min(non-nil of the two)    (nil if both nil)
```
Formatting: `< 1 h` → "< 1 h"; `< 48 h` → "N h"; `< 60 d` → "~N d"; `≥ 60 d` → "> 60 d". Popover shows `runway_7d · runway_today today` when both exist, else the one that exists. With auto-reload enabled and `remaining ≤ auto_reload_below`, the label becomes "reloads at $X" and band is forced `watch`.

## Bands (thresholds from `09`; defaults shown)

Evaluated in this order; first match wins:
1. `unknown` — mode `spend_only`, or no anchor, or `runway_min == nil`, or `M ≥ remaining`.
2. `critical` — `remaining < dollar_floor` (500 cents) OR `runway_min < critical_days` (2 d).
3. `low` — `runway_min < low_days` (7 d).
4. `watch` — `runway_min < watch_days` (14 d).
5. `healthy`.
`stale` is NOT a band. It is an overlay: `now − last_success_at > stale_multiplier × interval` (default 3). Stale dims the card and switches the glyph to the dashed outline; the band keeps its last value.
Band transitions are written to `band_state` with `inputs_json` and logged `ui.band_change` (`07`).

## Drift (by-model table, account page)

For each model, over CLOSED days in the selected range where a provider cost row exists for that model (OpenAI: `line_item` mapped to model by exact model name within the line item string; Anthropic: `description` grouping provides `model`):
`drift = (spend_est − spend_truth) / spend_truth`. Flag when `|drift| > drift_threshold` (10 %). When no provider cost row exists for the model, show "—" and do not compute.

## Cache savings (tile)

```
saved = Σ cacheRead × (in − cache_read_rate)  − Σ cacheWrite5m × (cache_write_5m_rate − in) − Σ cacheWrite1h × (cache_write_1h_rate − in)
```
i.e. NET of write premiums. Computed only from `source='provider'` buckets for Anthropic, and from harness buckets for providers where per-response cache fields exist. For OpenAI the tile shows "not computed — OpenAI aggregate cache counts are unreliable" (quirk in `02`).

## Currency

Each account has one `currency`. All of an account's figures are shown in that currency with the correct symbol (`$`, `CN¥`). Cross-account totals (Overview subline) sum USD accounts only and append "+ N non-USD" when others exist. No conversion in V1.

## Definition of done
- Normalizer tests: one fixture per row of the normalizer table, asserting every class.
- Price lookup tests: each of the 6 steps hit by a dedicated case; `V5` zero-price case returns nil.
- Runway tests: table-driven over `{remaining, burn_7d, burn_today, floor}` → `{runway_min, band}` including all nil combinations and the auto-reload override.
- Band test: `M ≥ remaining` yields `unknown`.
