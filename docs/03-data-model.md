# 03 — Data model, retention, durability

Engine: SQLite via GRDB (`DatabasePool`). File: `~/Library/Application Support/TokenBe/tokenbe.sqlite`. Backup: `tokenbe.sqlite.bak` (same folder). All timestamps are RFC3339 UTC strings with millisecond precision. All money is integer minor units (`*_cents`) with an explicit `currency` (`USD`, `CNY`). All ids are UUIDv7 strings unless the provider supplies one.

## PRAGMAs (set on every connection open, in this order)

```
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA auto_vacuum = INCREMENTAL;      -- must be set before any table exists; the writer connection sets it on open (Q-024)
PRAGMA cache_size = -2000;             -- 2 MB
PRAGMA mmap_size = 0;
PRAGMA temp_store = MEMORY;
PRAGMA busy_timeout = 5000;
```
On idle (no write for 60 s): `PRAGMA wal_checkpoint(TRUNCATE); PRAGMA optimize;`. After roll-up: `PRAGMA incremental_vacuum;`.

## Schema (migration 001 — authoritative DDL)

```sql
CREATE TABLE schema_version (version INTEGER NOT NULL, applied_at TEXT NOT NULL);

CREATE TABLE account (
  id              TEXT PRIMARY KEY,
  provider        TEXT NOT NULL CHECK (provider IN ('openai','anthropic','openrouter','deepseek','xai')),
  label           TEXT NOT NULL,
  keychain_ref    TEXT NOT NULL,                         -- Keychain account name; never the secret
  balance_mode    TEXT NOT NULL CHECK (balance_mode IN ('direct','anchored','spend_only')),
  currency        TEXT NOT NULL DEFAULT 'USD',
  capabilities    TEXT NOT NULL,                         -- JSON Capabilities (04)
  org_id          TEXT, org_name TEXT,
  auto_reload_enabled INTEGER NOT NULL DEFAULT 0,
  auto_reload_to_cents INTEGER, auto_reload_below_cents INTEGER,
  paused          INTEGER NOT NULL DEFAULT 0,            -- 1 = scheduler skips every job for this account (09)
  interval_override_json TEXT,                           -- JSON {usage?,cost?,balance?,keys?} seconds; NULL = globals (09)
  created_at      TEXT NOT NULL,
  UNIQUE (provider)                                      -- V1: one account per provider
);

CREATE TABLE provider_key (
  account_id       TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  provider_key_id  TEXT NOT NULL,                        -- OpenAI key_…, Anthropic apikey_…, OpenRouter hash
  name             TEXT, redacted TEXT, project_id TEXT, workspace_id TEXT,
  status           TEXT NOT NULL DEFAULT 'active',
  first_seen_at    TEXT NOT NULL, last_seen_at TEXT NOT NULL,
  PRIMARY KEY (account_id, provider_key_id)
);

CREATE TABLE app (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL UNIQUE,                     -- immutable harness tag / slug (06 regex)
  display_name TEXT NOT NULL,                            -- editable; defaults to name
  created_at   TEXT NOT NULL,
  is_auto      INTEGER NOT NULL DEFAULT 0                -- 1 = created from an unknown harness tag
);

CREATE TABLE app_binding (
  app_id      TEXT NOT NULL REFERENCES app(id) ON DELETE CASCADE,
  account_id  TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('provider_key','harness_tag')),
  value       TEXT NOT NULL,                             -- provider_key_id or harness tag
  PRIMARY KEY (account_id, kind, value)
);

CREATE TABLE usage_bucket (
  account_id      TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  bucket_start    TEXT NOT NULL,                         -- RFC3339 UTC, aligned to width
  bucket_width    TEXT NOT NULL CHECK (bucket_width IN ('1h','1d','1mo')),
  model           TEXT NOT NULL,                         -- '*' when unknown (OpenRouter per-key rows)
  provider_key_id TEXT NOT NULL DEFAULT '',              -- '' when not grouped
  service_tier    TEXT NOT NULL DEFAULT '',
  source          TEXT NOT NULL CHECK (source IN ('provider','harness','rollup')),
  input_uncached  INTEGER NOT NULL DEFAULT 0,
  cache_write_5m  INTEGER NOT NULL DEFAULT 0,
  cache_write_1h  INTEGER NOT NULL DEFAULT 0,
  cache_read      INTEGER NOT NULL DEFAULT 0,
  output          INTEGER NOT NULL DEFAULT 0,
  reasoning       INTEGER NOT NULL DEFAULT 0,
  requests        INTEGER NOT NULL DEFAULT 0,
  est_cost_cents  INTEGER,                               -- NULL when any class is unpriced
  unpriced        INTEGER NOT NULL DEFAULT 0,            -- 1 when est_cost_cents is NULL because of price book
  provisional     INTEGER NOT NULL DEFAULT 1,            -- 1 until bucket_end + usageLag < fetched_at
  fetched_at      TEXT NOT NULL,
  PRIMARY KEY (account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source)
);
CREATE INDEX usage_bucket_time ON usage_bucket(account_id, bucket_width, bucket_start);

CREATE TABLE cost_bucket (
  account_id    TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  day           TEXT NOT NULL,                           -- YYYY-MM-DD UTC
  group_kind    TEXT NOT NULL CHECK (group_kind IN ('api_key_id','workspace_id','line_item','description','total')),
  group_key     TEXT NOT NULL,
  amount_cents  INTEGER NOT NULL,
  currency      TEXT NOT NULL,
  provisional   INTEGER NOT NULL DEFAULT 1,
  fetched_at    TEXT NOT NULL,
  PRIMARY KEY (account_id, day, group_kind, group_key)
);

CREATE TABLE balance_snapshot (
  account_id    TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  ts            TEXT NOT NULL,
  currency      TEXT NOT NULL,
  amount_cents  INTEGER NOT NULL,
  granted_cents INTEGER, topped_up_cents INTEGER,
  is_available  INTEGER,
  PRIMARY KEY (account_id, ts, currency)
);

CREATE TABLE harness_event (
  provider     TEXT NOT NULL,
  request_id   TEXT NOT NULL,
  account_id   TEXT REFERENCES account(id) ON DELETE SET NULL,
  app_tag      TEXT NOT NULL,
  provider_key_id TEXT,                                  -- resolved from key_hint when a provider_key.redacted ends with the same 4 chars
  key_hint     TEXT,                                     -- last 4 chars only, never more
  ts           TEXT NOT NULL,
  future_ts    INTEGER NOT NULL DEFAULT 0,               -- 1 when ts > ingested_at + 5 min (06)
  model        TEXT NOT NULL,
  status       INTEGER NOT NULL,                         -- 1 = ok, 0 = error (06 status field)
  usage_json   TEXT NOT NULL,                            -- verbatim provider usage object
  classes_json TEXT,                                     -- normalized TokenClasses, NULL if normalization failed
  est_cost_cents INTEGER,
  source_file  TEXT NOT NULL, source_line INTEGER NOT NULL,
  ingested_at  TEXT NOT NULL,
  PRIMARY KEY (provider, request_id)
);
CREATE INDEX harness_event_ts ON harness_event(account_id, ts);

CREATE TABLE ingest_file (
  path        TEXT PRIMARY KEY,
  inode       INTEGER NOT NULL,
  offset      INTEGER NOT NULL DEFAULT 0,               -- bytes fully processed
  last_size   INTEGER NOT NULL DEFAULT 0,
  last_mtime  TEXT NOT NULL,
  state       TEXT NOT NULL CHECK (state IN ('active','ingested','rejected')),
  lines_ok    INTEGER NOT NULL DEFAULT 0, lines_bad INTEGER NOT NULL DEFAULT 0, lines_dup INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE ledger_event (
  id            TEXT PRIMARY KEY,
  account_id    TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  ts            TEXT NOT NULL,
  kind          TEXT NOT NULL CHECK (kind IN ('anchor','topup','reconcile','note','auto_zero')),
  amount_cents  INTEGER,
  currency      TEXT,
  note          TEXT,
  source        TEXT NOT NULL CHECK (source IN ('user','system'))
);
CREATE INDEX ledger_event_ts ON ledger_event(account_id, ts);

CREATE TABLE price_snapshot (
  version     TEXT PRIMARY KEY,                           -- YYYY-MM-DD of fetch, or 'bundled-<appversion>'
  fetched_at  TEXT NOT NULL,
  etag        TEXT,
  sha256      TEXT NOT NULL,
  json        BLOB NOT NULL,
  is_current  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE price_override (
  model       TEXT PRIMARY KEY,
  json        TEXT NOT NULL,                              -- same keys as price feed entry
  updated_at  TEXT NOT NULL
);

CREATE TABLE poll_state (
  account_id           TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  job                  TEXT NOT NULL,                     -- 'usage'|'cost'|'balance'|'keys'
  last_attempt_at      TEXT, last_success_at TEXT,
  last_error_class     TEXT, last_error_message TEXT,
  consecutive_failures INTEGER NOT NULL DEFAULT 0,
  circuit_open_until   TEXT,
  cursor               TEXT,                              -- provider paging cursor if a page sequence was interrupted
  last_raw             BLOB,                              -- ≤ 64 KB, redacted
  PRIMARY KEY (account_id, job)
);

CREATE TABLE band_state (
  account_id  TEXT PRIMARY KEY REFERENCES account(id) ON DELETE CASCADE,
  band        TEXT NOT NULL,                              -- healthy|watch|low|critical|unknown
  since       TEXT NOT NULL,
  inputs_json TEXT NOT NULL                               -- remaining, burn_7d, burn_today, floor → for log traceability
);
```

## Retention tiers (job runs in the daily background activity, `04 § Scheduling`)

| Tier | Rows | Kept | Action after window |
|---|---|---|---|
| hourly `usage_bucket` (`1h`, source provider/harness) | per account × model × key × tier | 90 days | summed into `1d` rows with `source='rollup'`, then deleted |
| `harness_event` | per request | 90 days | contribution is already in `1h`/`1d` buckets (source harness); rows deleted |
| `balance_snapshot` | per poll | 7 days at full rate; then first snapshot of each day kept forever | others deleted |
| daily `usage_bucket` (`1d`) | | forever | after 400 days additionally summed into `1mo` rows (kept alongside) |
| `cost_bucket` | | forever | never touched |
| `ledger_event`, `app`, `app_binding`, `provider_key`, `price_override` | | forever | never touched |
| `price_snapshot` | | current + previous 3 | older deleted |
| `poll_state.last_raw` | | last success only | overwritten |

Roll-up is idempotent: it is keyed on bucket primary keys; re-running produces identical rows.

## Migrations

- Forward-only. Numbered `001_initial.sql`, `002_….sql`. Applied inside one transaction each. `schema_version` appended on success.
- **`poll_state.last_error_message`** holds the failure's human message (02 probe messages, `CoreStrings`), which the account page's Sources strip shows; the raw cause (status, redacted body) goes to the `poll.failed` record's `detail` (07, Q-036). A success clears both error columns.
- **Seed rows in `001_initial.sql`:** `schema_version(version=1, applied_at=now)`; `app(id='app_unassigned', name='unassigned', display_name='Unassigned', created_at=now, is_auto=1)` — the V4 sentinel. Runtime seeds (not in the migration): `price_snapshot('bundled-<appversion>')` at first launch when no current snapshot exists; four `poll_state` rows (`usage`,`cost`,`balance`,`keys`) when an account is created, regardless of capabilities (jobs the provider lacks stay `last_attempt_at NULL`).
- Columns are never dropped or renamed. Deprecated columns get a comment in the migration file and are ignored.
- Every migration ships with a fixture DB produced by the previous version (`Fixtures/db/vNNN.sqlite`) and a test that migrates it and asserts row counts.
- A migration failure aborts launch with an alert that names the migration, the error, and the backup path. It never deletes the DB.

## Durability

- Launch: `PRAGMA quick_check` (full `integrity_check` weekly in the background activity). Failure → log `db.integrity_failed`, copy the corrupt file to `tokenbe.sqlite.corrupt-<ts>`, restore from `.bak`, alert the user with both paths.
- Daily: online backup via GRDB `backup(to:)` into a temp file, then atomic rename to `tokenbe.sqlite.bak`. Log `db.backup` with size and duration.
- Export (Settings → Advanced): JSON document `{ "schema_version":N, "exported_at":…, "accounts":[…], "provider_keys":[…], "apps":[…], "app_bindings":[…], "usage_buckets":[…], "cost_buckets":[…], "balance_snapshots":[…], "ledger_events":[…], "price_overrides":[…] }`. Secrets are NOT exported. Import of the same document into an empty DB reproduces every table except `poll_state` and `ingest_file`.
- CSV export: one file per table listed above, RFC4180, header row, UTF-8.

## Definition of done
- Fresh launch creates the DB with migration 001 and the PRAGMAs above (asserted by test reading `PRAGMA journal_mode` etc.).
- `LOAD-1` (`11`) produces < 250 MB after roll-ups and passes `integrity_check`.
- Export → wipe → import round-trips with identical row counts in every exported table.
