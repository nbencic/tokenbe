-- 002_providers.sql — account.provider accepts the providers of Q-062 (03 § Migration 002).
-- SQLite cannot alter a CHECK constraint, so `account` is rebuilt with SQLite's documented procedure for "other
-- kinds of table schema changes": create the new table, copy, drop the old one, rename. The migrator runs every
-- migration with foreign_keys OFF (set outside the transaction) and requires an empty PRAGMA foreign_key_check before
-- it commits, so dropping the old `account` deletes no row of the nine tables that reference it. Every column,
-- default and constraint of 001's `account` is kept; only the provider list grows. `account` has no index, trigger
-- or view of its own besides UNIQUE (provider).

CREATE TABLE account_new (
  id              TEXT PRIMARY KEY,
  provider        TEXT NOT NULL CHECK (provider IN ('openai','anthropic','openrouter','deepseek','xai',
                                                    'moonshot','novita','stepfun','siliconflow','deepinfra')),
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

INSERT INTO account_new (id, provider, label, keychain_ref, balance_mode, currency, capabilities, org_id, org_name,
                         auto_reload_enabled, auto_reload_to_cents, auto_reload_below_cents, paused,
                         interval_override_json, created_at)
  SELECT id, provider, label, keychain_ref, balance_mode, currency, capabilities, org_id, org_name,
         auto_reload_enabled, auto_reload_to_cents, auto_reload_below_cents, paused,
         interval_override_json, created_at
  FROM account;

DROP TABLE account;

ALTER TABLE account_new RENAME TO account;
