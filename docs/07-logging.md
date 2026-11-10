# 07 — Logging (mandatory, local, redacted)

Rule: **every** `catch`, every `else` branch that represents an unexpected state, every retry, every scheduler decision and every state transition writes a log record. A silent `catch {}` or `try?` that discards an error is a build failure (SwiftLint rule `tokenbe_no_silent_catch`, see 10).

## Sinks

1. `os.Logger(subsystem: "dev.bathyon.tokenbe", category: <category>)` — always on; visible in Console.app.
2. NDJSON file sink — always on; `~/Library/Logs/TokenBe/tokenbe-YYYY-MM-DD.ndjson`.
   - Written by a single actor `LogSink` through a bounded `AsyncStream` (capacity 4 096; on overflow drop the record and increment `dropped` which is itself logged every 60 s as `app.log_dropped {count}`).
   - Flushed on a 1 s timer or when the buffer exceeds 64 KiB, and synchronously on `applicationWillTerminate`, on the crash handler path, and after every `.error`/`.fault` record.
   - Rotation: new file at local midnight or when the file exceeds 50 MiB (suffix `-N`). Delete files older than `tb.log.retentionDays` (default 14). Total cap 300 MiB: delete oldest first.
3. Breadcrumb ring buffer — last 500 records in memory (any level), dumped into the diagnostics bundle and attached to crash records.

## Record shape (one JSON object per line; keys in this order)

```json
{"ts":"2026-11-09T14:03:21.512Z","lvl":"error","cat":"poll.openai","evt":"poll.failed","msg":"usage poll failed","acct":"openai","job":"usage","attempt":2,"err":{"type":"PollError.transport","code":-1001,"desc":"The request timed out."},"dur_ms":10012,"ctx":{"url":"https://api.openai.com/v1/organization/usage/completions","status":null},"pid":4132,"thr":"actor:AccountPoller(openai)","v":"1.0.0 (112)"}
```
- `lvl` ∈ `debug` `info` `notice` `warn` `error` `fault`.
- `cat` ∈ `app` `sched` `poll.<provider>` `normalize` `price` `ledger` `ingest` `keychain` `db` `ui` `update` `crash`.
- `evt` is a stable dotted identifier (table below). New events MUST be added to this table in the same PR.
- `ctx` is a flat object of primitives; never nested more than one level; max 2 KiB after redaction (truncate strings to 512 chars with `…`). Keys are written in sorted order; if the cap is still exceeded, the remaining keys are dropped and `ctx_truncated: true` is added (Q-007). Exception: `crash.signal` carries its breadcrumbs as one string and is exempt from the cap (Q-008).
- Top-level `acct`, `job`, `attempt`, `err` and `dur_ms` are omitted when they do not apply; `ts`, `lvl`, `cat`, `evt`, `msg`, `ctx`, `pid`, `thr`, `v` are always present (Q-007).
- Durations in `dur_ms` as integers.

## Redaction (applied to EVERY string before it reaches any sink, including `os.Logger`)

Regexes applied in order, replacement `«redacted:<kind>»`:
1. `sk-[A-Za-z0-9_\-]{8,}` → `«redacted:key»`
2. `sk-ant-[A-Za-z0-9_\-]{8,}` → `«redacted:key»`
3. `(?i)(authorization|x-api-key|x-goog-api-key)(["']?)\s*[:=]\s*(["']?)(?:[A-Za-z]+\s+)?[^\s"',}]+` → `$1$2: $3«redacted:header»` (an optional auth-scheme word such as `Bearer`/`Basic` is consumed with the value, and JSON-quoted names and values are covered; Q-006)
4. `(?i)bearer\s+[^\s"',}]{8,}` → `Bearer «redacted:token»` (token characters include `+ / =`; Q-006)
5. `xai-[A-Za-z0-9]{8,}` → `«redacted:key»`
6. `sk-or-v1-[A-Za-z0-9]{8,}` → `«redacted:key»`
7. Any occurrence of a value currently held in the in-memory key cache → `«redacted:key»` (exact substring pass, longest value first; covers unknown formats)

Redaction runs before truncation, so a key cut by the 512-character limit cannot slip past patterns 1–6.
A unit test feeds each pattern plus a real-shaped fake key and asserts no sink output contains more than the last 4 chars.

## Level policy
- `debug`: per-request details, bucket upserts, dedup hits. OFF by default (`tb.log.level` default `info`).
- `info`: every poll start/success, scheduler ticks, ingest file events, band changes, settings changes.
- `warn`: retries, stale, drift detected, fallback multipliers, unknown keys, Low Power mode slowdowns.
- `error`: a job failed after its retries, decode/schema drift, keychain failure, DB write failure, FSEvents failure.
- `fault`: DB corruption, migration failure, unrecoverable keychain state, crash.

## Mandatory events (complete list for V1; emit exactly these names)

| evt | lvl | required ctx |
|---|---|---|
| `app.launch` | info | version, build, macOS, lowPower, launchAtLogin |
| `app.terminate` | info | reason |
| `app.log_dropped` | warn | count |
| `app.log_sink_failed` | error | op (`mkdir`,`open`,`write`,`rotate`,`retention`), path, err — emitted to os.Logger and breadcrumbs only, never back into the failing sink; once per failure streak |
| `app.settings_changed` | info | key, old, new, clamped (bool), source (`user`,`system`) |
| `app.settings_reset` | info | keys_removed |
| `app.login_item_failed` | error | err (SMAppService) |
| `app.network_changed` | info | online (bool), interface |
| `app.diagnostics_exported` | info | path, bytes, files |
| `sched.clock_jump` | warn | wall_delta_s, mono_delta_s, tz (bool) |
| `sched.low_power` | info | enabled |
| `sched.overlap_skipped` | warn | acct, job |
| `sched.overrun` | error | acct, job, phase (`fetch`,`decode`,`write`), dur_ms |
| `sched.tick` | debug | job, acct, due_in_s |
| `sched.skip` | info | job, acct, reason (`paused`,`circuit_open`,`low_power`,`offline`) |
| `sched.daily_start` / `sched.daily_end` | info | dur_ms, steps_ok, steps_failed |
| `poll.start` | info | acct, job |
| `poll.ok` | info | acct, job, dur_ms, rows, cursor |
| `poll.retry` | warn | acct, job, attempt, delay_ms, err |
| `poll.failed` | error | acct, job, attempts, err |
| `poll.rate_limited` | warn | acct, job, retry_after_s |
| `poll.auth_failed` | error | acct, job, http_status |
| `poll.circuit_open` / `poll.circuit_close` | warn/info | acct, job, until |
| `poll.schema_drift` | error | acct, job, missing_keys, sample (≤512 chars redacted) |
| `poll.unknown_keys` | info | acct, job, keys (once per day) |
| `poll.provider_rule` | warn | acct, job, rule (e.g. `anthropic_requires_org`, `deepseek_no_usage_api`) |
| `poll.write_incomplete` | error | acct, job, expected, written — V2: a usage page's stored rows do not add up to its results; the page is rolled back (Q-029) |
| `normalize.negative` | warn | provider, field, value |
| `normalize.failed` | error | provider, missing_key, request_id? |
| `normalize.unknown_keys` | info | provider, keys |
| `price.feed_ok` | info | entries, etag, bytes |
| `price.feed_failed` | warn | err, reason (`transport`,`shape`,`size`), using_cached_from |
| `price.parse_failed` | warn | err, bytes |
| `price.stale` | warn | snapshot_age_days |
| `price.unpriced` | warn | provider, model (once per model per day) |
| `price.fallback_multiplier` | info | provider, model, field |
| `price.override_set` | info | model |
| `price.repriced` | info | acct, rows, snapshot_version |
| `ledger.anchor_set` / `ledger.topup` / `ledger.reconcile` | info | acct, amount_cents, source |
| `ledger.auto_zero` | warn | acct, http_status |
| `ledger.drift` | warn | acct, model, drift_pct |
| `ledger.harness_drift` | warn | acct, day, delta_cents |
| `ingest.folder_recreated` | warn | path |
| `ingest.folder_unwritable` | error | path, err |
| `ingest.fsevents_failed` | error | err, fallback_poll_s |
| `ingest.skipped` | info | path, reason (`hidden`,`symlink`,`dir`,`ext`) |
| `ingest.inode_changed` / `ingest.truncated` | warn | file, old, new |
| `ingest.file_rejected` | warn | file, head (≤200 chars redacted) |
| `ingest.bad_json` / `ingest.bad_version` / `ingest.unknown_provider` / `ingest.bad_app` / `ingest.line_too_long` | warn | file, line_no |
| `ingest.key_hint_truncated` / `ingest.unknown_fields` / `ingest.key_hint_ambiguous` | info | file, field(s) |
| `ingest.duplicate` | debug | provider, request_id |
| `ingest.duplicate_conflict` | warn | provider, request_id |
| `ingest.app_created` | info | app, provider |
| `ingest.future_ts` / `ingest.too_old` | warn | file, line_no, ts |
| `ingest.large_file` | warn | file, bytes |
| `ingest.burst` | info | file, lines |
| `ingest.read_failed` | error | file, err, attempt |
| `ingest.moved` | info | file, to (`ingested`,`rejected`) |
| `ingest.start` | info | files, mode (`fsevents`,`poll`) |
| `ingest.stop` | info | reason |
| `keychain.read_failed` / `keychain.write_failed` / `keychain.delete_failed` | error | acct, osstatus |
| `keychain.missing` | error | acct |
| `keychain.access_denied` | fault | acct, osstatus |
| `db.open` | info | path, size_bytes, journal_mode, page_size |
| `db.migrate` | info | from, to, dur_ms |
| `db.migrate_failed` | fault | from, to, err |
| `db.quick_check` / `db.integrity_check` | info | result, dur_ms |
| `db.integrity_failed` | fault | check, result, corrupt_copy |
| `db.corrupt` | fault | path, moved_to |
| `db.restore` | warn | from_backup |
| `db.backup` | info | bytes, dur_ms |
| `db.backup_failed` | error | err |
| `db.vacuum` | info | pages_freed |
| `db.rollup` | info | tier, rows_in, rows_out |
| `db.export` | info | kind (`json`,`csv_tables`,`csv_view`), path, rows |
| `db.import` | info | path, rows |
| `db.import_failed` | error | path, err |
| `db.busy` | warn | op, waited_ms |
| `ui.popover_open` / `ui.popover_close` | debug | dur_ms open |
| `ui.band_change` | info | acct, from, to, inputs (remaining, burn_7d, burn_today, runway_min) |
| `ui.notification_sent` | info | acct, band, suppressed_by_quiet_hours |
| `ui.notification_denied` | warn | — |
| `ui.hotkey_failed` | warn | shortcut, osstatus |
| `ui.error` | error | view, err |
| `update.check_ok` | info | latest, current, newer |
| `update.check_failed` | warn | err |
| `crash.previous_launch` | fault | signal_or_exception, breadcrumbs_attached |
| `crash.signal` | fault | signal, breadcrumbs (last 50) |

## Crash handling
- Install `NSSetUncaughtExceptionHandler` and signal handlers for `SIGABRT SIGBUS SIGSEGV SIGILL SIGTRAP SIGFPE`. In the handler: write ONE line `{"evt":"crash.signal",…}` with the last 50 breadcrumbs using a pre-allocated buffer and `write(2)` (no allocations, no Swift runtime calls that may lock). Then re-raise.
- At next launch, if `~/Library/Application Support/TokenBe/.running` exists → previous run did not terminate cleanly → log `crash.previous_launch`. Create `.running` after this check; remove on clean terminate.

## Diagnostics bundle (Settings → Advanced → "Export diagnostics…")
Zip named `TokenBe-diagnostics-YYYYMMDD-HHMMSS.zip` containing: last 3 NDJSON log files, `breadcrumbs.ndjson`, `settings.json` (all `tb.*` keys), `schema.sql` (output of `.schema`), `db-stats.json` (row counts per table, size, page count, freelist), `poll_state.json` (with `last_raw` already redacted), `price-overrides.json`, `environment.json` (macOS, app version, lowPower, locale, timezone). Never includes `tokenbe.sqlite` itself and never includes anything from Keychain. SEC-1 (11) greps the bundle for key patterns.

## Definition of done
- Grep the source tree: zero `catch {}` / `catch { }` / `try?` outside the allow-listed file `Allowlist.swift` (which must be empty in V1).
- Redaction tests pass for all 7 patterns.
- Unit test: a crash-handler dry run writes a parseable NDJSON line.
- Every row of the mandatory events table is referenced by at least one call site (script `scripts/check-log-events.sh` greps `evt: "` literals against this table and fails on missing or unknown).
