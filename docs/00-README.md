# TokenBe — Engineering Documentation Set (V1)

Status: AUTHORITATIVE for V1. Last revised 2026-11-09.
Owner: Nikola Benčić (nbencic). Product: open-source, Swift-native macOS menu-bar app.
UI source of truth (visuals): Paper file "TokenBe — App" → https://app.paper.design/file/01M6ZTCNRVZYN35QB3XX0HQJ2D
Behaviour source of truth: THESE DOCUMENTS. Where Paper and these docs disagree on behaviour, these docs win. Where they disagree on visuals, Paper wins.

## How an implementing agent MUST use this set

1. Read `12-agent-rules.md` FIRST. It defines what you may decide, what you must not do, and what to do when something is unspecified.
2. Read the rest in numeric order once, fully, before writing code.
3. Every file ends with a "Definition of done" or "Acceptance" block. A task is finished only when every line of that block is true.
4. Never infer a provider field name, a default value, a threshold, a path, or a cadence. All of them are stated. If one is missing, follow `12-agent-rules.md § Unspecified`.

## Document map

| File | Contents | Read when |
|---|---|---|
| `01-product-scope.md` | What V1 is, who it is for, what is explicitly OUT, acceptance criteria | Always |
| `02-provider-apis.md` | Exact endpoints, auth, parameters, response fields, lags, quirks per provider | Writing any adapter |
| `03-data-model.md` | Full SQLite DDL, retention tiers, migration rules, backup | Touching storage |
| `04-architecture.md` | Modules, concurrency model, scheduler, error taxonomy, retry, invariants, resource targets | Always |
| `05-normalization-pricing-runway.md` | Token-class normalization per provider, price lookup, cost formulas, runway, bands, drift | Writing math |
| `06-harness-ingest.md` | Drop-folder protocol, line format, FSEvents tailing, dedup, attribution precedence | Ingest module |
| `07-logging.md` | NDJSON schema, categories, mandatory events, redaction, rotation, diagnostics bundle | Every module |
| `08-ui-spec.md` | Screens, elements, states, copy, tokens | UI work |
| `09-settings-spec.md` | Every setting: key, type, default, range, effect | Settings + any consumer of a setting |
| `10-repo-build-release.md` | Repo layout, Package.swift, build, signing, Homebrew, versioning | Project setup, release |
| `11-testing.md` | Fixtures, unit/integration/acceptance matrix | Every PR |
| `12-agent-rules.md` | Working rules for the implementing agent | FIRST |
| `13-decisions.md` | Closed decisions with rationale; the open list with defaults | When tempted to choose |
| `14-development-plan.md` | Phases → stages → steps, seams, human gates, per-stage inventory and machine-checked definition of done, coverage matrices | Before starting any stage; `scripts/verify-stage.sh` |
| `QUESTIONS.md` | Append-only log of judgment calls made during implementation (format in `12 § R3`) | Whenever something is unspecified |
| `postmortems/` | One blameless postmortem per stage (`stage-<id>.md`) and per phase (`phase-<n>.md`); template and rules in `14 § 0.6` | At the start of every stage (read open carry-forward actions); at the end of every stage and phase (write) |
| `reporters/` | Reference harness reporter snippets (Python, Node) shipped verbatim in the repo README | Ingest module, README |

## Non-negotiables (summary; details in the files)

- ONE third-party dependency: GRDB. No others without a written decision in `13-decisions.md`.
- NO pass-through proxy, NO virtual keys, NO Claude Code / Codex log ingestion, NO subscription quota cards, NO local HTTP API, NO Gemini, NO webhooks, NO in-app updater in V1.
- Every error, retry, skipped poll, overlap, clock jump, decode anomaly and ledger change is logged as one NDJSON record (`07-logging.md`).
- Estimates are always rendered with `≈` and a `±` band. Direct balances never are.
- Keys live only in Keychain. They never appear in the database, logs, exports, or crash reports.
- Swift 6 language mode with strict concurrency. No `@unchecked Sendable` without a comment citing the invariant that makes it safe.

## Glossary (use these words, exactly)

- **Account** — one pasted key for one provider. Label chosen by user.
- **Provider key** — a key discovered under an account via the provider's key-listing endpoint (OpenAI, Anthropic, OpenRouter). Identified by provider key id, never by secret.
- **App** — a user-facing attribution bucket. Bound to provider keys and/or harness tags.
- **Harness report / harness line** — one JSON line a user's program appends to the drop folder describing one request.
- **Anchor** — a user-entered balance at a point in time; the start of an estimate.
- **Remaining** — direct balance (direct providers) or `anchor + topups − spend since anchor` (anchored providers).
- **Burn** — spend per day. `burn_7d` and `burn_today` are defined in `05`.
- **Runway** — remaining ÷ burn, in days/hours. Two paces are always computed.
- **Band** — the health state: healthy / watch / low / critical / unknown.
- **Stale** — a source whose last success is older than `stale_multiplier × poll interval`.
- **Direct** — a provider that exposes a balance endpoint (OpenRouter, DeepSeek, xAI).
- **Anchored** — a provider without a balance endpoint (OpenAI, Anthropic).
