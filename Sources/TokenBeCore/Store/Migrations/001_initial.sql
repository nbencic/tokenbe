-- 001_initial.sql — the full DDL of docs/03-data-model.md § Schema, verbatim, plus the seed rows of 03 § Migrations.
-- Forward-only: never edit this file once released; later changes are 002_….sql (03, 12 R7).
-- PRAGMA auto_vacuum = INCREMENTAL is set by AppDatabase on the writer connection before any table exists (Q-024):
-- GRDB's WAL setup creates a scratch table before this file runs, after which auto_vacuum can no longer change.

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

-- Seed rows (03 § Migrations). Timestamps are RFC3339 UTC with milliseconds.
INSERT INTO schema_version (version, applied_at) VALUES (1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
INSERT INTO app (id, name, display_name, created_at, is_auto)
  VALUES ('app_unassigned', 'unassigned', 'Unassigned', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), 1);  -- V4 sentinel
