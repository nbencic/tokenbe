# 01 — Product scope (V1)

## One sentence

TokenBe is a macOS menu-bar app that shows, per LLM provider account, how much money is left and how long it lasts, attributes spend to the user's own apps by API key, and never requires a visit to a provider console for that.

## Target user

A single person who pays for LLM APIs and runs their own programs ("harnesses") against them on demand: polling jobs, agents, scripts. They have one or more provider accounts, often several API keys per account (one per project), and they want to know (a) when an account will run dry and (b) which of their programs is spending.

Not a target in V1: teams, subscription-plan users (Claude Max, ChatGPT Plus), people who want to proxy their traffic.

## V1 IN

| # | Capability | Detail |
|---|---|---|
| S1 | One key per provider | Adapters for OpenAI (admin key), Anthropic (admin key), OpenRouter (management key), DeepSeek (standard key), xAI (standard key). Max one account per provider. **The 1.0.0 Release build offers only providers whose live-API fixtures were recorded** (`13 § D-verified-providers`): OpenAI, DeepSeek, xAI (the last two subject to key availability). Anthropic and OpenRouter are compiled and tested on synthetic fixtures and hidden until a contributor records fixtures. |
| S2 | Remaining funds | Direct from OpenRouter / DeepSeek / xAI. Estimated (anchor − spend) for OpenAI / Anthropic. Estimates rendered `≈ $N ± M`. |
| S3 | Runway | Two paces (7-day, today). Band from the worse. Hard dollar floor. |
| S4 | Per-app attribution | By provider key id (OpenAI, Anthropic, OpenRouter). By harness report (DeepSeek, xAI, and optional for all). |
| S5 | Ledger | Anchor, top-up, reconcile, note events. History never deleted by the app. |
| S6 | Popover | Ranked account cards, alert banner, empty state, day-1 state. |
| S7 | Dashboard | Overview page (headline, runway board, spend-by-day chart, apps this period, cache savings tile), per-account page (header, badges, numbers strip, by-app table, by-model reconciliation table, sources strip, ledger list), Apps page. Pricing lives in Settings → Sources → Price book. Exactly as `08`. |
| S8 | Settings | General, Accounts, Sources, Alerts, Privacy, Advanced as specified in `09`. |
| S9 | Onboarding | 3-step sheet: provider → key (probe + capabilities) → balance anchor (anchored providers only). |
| S10 | Pricing | Bundled LiteLLM snapshot, daily refresh, per-model overrides, unpriced-model surfacing. |
| S11 | Notifications | macOS notifications on band change, quiet hours, optional Shortcut. |
| S12 | Logging | NDJSON file log + OSLog, redaction, diagnostics bundle (`07`). |
| S13 | Data durability | SQLite WAL, tiered retention, daily online backup, integrity check at launch, JSON export/import. |

## V1 OUT (do not build, do not stub, do not leave TODOs for)

- Pass-through HTTP proxy, virtual keys, base-URL snippets.
- Claude Code / Codex / OpenCode local log ingestion.
- Subscription quota (OAuth `api/oauth/usage`) cards.
- Local HTTP API for scripts/widgets.
- Gemini / Google Cloud Billing.
- Webhooks.
- In-app updater (Sparkle). V1 has a daily GitHub releases check that opens the release page.
- Multiple accounts per provider.
- Currency conversion. Amounts are shown in the provider's billing currency (`05 § Currency`).
- Dark-mode-specific artwork (system colours only; it must not break in dark mode, it is not designed for it).
- WidgetKit widgets.
- Any form of telemetry.

## Acceptance criteria (all must pass on a clean macOS 15 machine)

| # | Criterion | Verification |
|---|---|---|
| A1 | Paste one key per provider → capability probe result shown within 10 s → first poll completes within 60 s → popover shows remaining and both runway paces. | Manual + `11 § E2E-2` |
| A2 | OpenAI (and, once verified, Anthropic) accounts show a **By app** table with human key names, tokens, estimated cost, and share, without opening any console. | `11 § AttributionTests` + `AppsBindingUITests` |
| A3 | A DeepSeek harness appending the documented JSONL creates app `weather-collector` with its own spend within 5 s of the file landing. Killing TokenBe mid-write and relaunching produces no duplicates and loses no lines. | E2E-3 |
| A4 | With networking disabled for 10 min: cards show stale, menu-bar glyph shows the stale shape, no crash, every failed poll is exactly one `error` record with redacted body. | E2E-5 |
| A5 | Every band change shown in the popover is traceable in the NDJSON log to the poll or ledger event that caused it. | E2E-9 |
| A6 | A model missing from the price book is flagged in the by-model table, excluded from runway, logged once per day at `warn`, and never silently priced at 0. | E2E-8 |
| A7 | Idle resource use with popover closed: ≤ 60 MB resident, ≤ 0.1 % average CPU over 1 h, no network except scheduled polls. | `powermetrics`, Activity Monitor |
| A8 | Database after a synthetic 5-year load (`11 § LOAD-1`) is < 250 MB and passes `PRAGMA integrity_check`. | Script |
| A9 | No secret appears in the database file, any log file, any export, or the diagnostics bundle. | `11 § SEC-1` grep harness |
| A10 | Build from a clean clone with `xcodebuild` succeeds with zero warnings in TokenBeCore. | CI |

## Definition of done for V1

All of A1–A10 pass; every stage of `14-development-plan.md` prints `STAGE <id> OK`; `13-decisions.md` has no row in state OPEN; `CHANGELOG.md` has a `1.0.0` section; a notarized `.dmg` and a Homebrew cask formula exist.
