# Stage 10.0.3 — Migration 002: the provider list (14 § Stage 10.0.3, Q-062, Q-063). Sourced by scripts/verify-stage.sh.

core=Sources/TokenBeCore
store=$core/Store
inventory=(
  $store/Migrations/002_providers.sql $store/Migrator.swift $store/Repository+Export.swift $core/TokenBeCore.swift
  Tests/Fixtures/db/schema_v1.sqlite Tests/TokenBeCoreTests/Migration002Tests.swift
  Tests/TokenBeCoreTests/MigrationTests.swift scripts/stages/2.1.sh scripts/stages/10.0.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 002: the account rebuild.
want_providers="'openai','anthropic','openrouter','deepseek','xai','moonshot','novita','stepfun','siliconflow','deepinfra'"
providers_002() { tr -d ' \n' < $store/Migrations/002_providers.sql | grep -qF "CHECK(providerIN($want_providers))"; }
check "002 widens account.provider to the ten providers of Q-062" providers_002
check "002 rebuilds account: create, copy every column, drop, rename" bash -c "f=$store/Migrations/002_providers.sql; grep -qF 'CREATE TABLE account_new (' \$f && grep -qF 'INSERT INTO account_new (id, provider, label, keychain_ref, balance_mode, currency, capabilities, org_id, org_name,' \$f && grep -qF 'DROP TABLE account;' \$f && grep -qF 'ALTER TABLE account_new RENAME TO account;' \$f"
same_columns() { # 002's account repeats 001's account line for line, except the provider CHECK
  local a b
  a="$(sed -n '/^CREATE TABLE account (/,/^);/p' $store/Migrations/001_initial.sql | grep -v 'provider  ' | sed '1d')"
  b="$(sed -n '/^CREATE TABLE account_new (/,/^);/p' $store/Migrations/002_providers.sql | grep -vE "provider  |^ +'moonshot'" | sed '1d')"
  [[ "$a" == "$b" ]] || { diff <(echo "$a") <(echo "$b"); return 1; }
}
check "002's account keeps every other line of 001's account (incl. UNIQUE (provider))" same_columns
check "the schema version is 2" grep -qF 'public static let schemaVersion = 2' $core/TokenBeCore.swift

# The migrator: foreign keys off outside the transaction, foreign_key_check before commit, back on always.
check "Migrator: foreign_keys OFF before, ON after (success and failure)" bash -c "test \$(grep -cF 'try db.execute(sql: \"PRAGMA foreign_keys = ON\")' $store/Migrator.swift) -eq 2 && grep -qF 'try db.execute(sql: \"PRAGMA foreign_keys = OFF\")' $store/Migrator.swift"
check "Migrator: foreign_key_check must be empty before commit" bash -c "grep -qF 'try Row.fetchAll(db, sql: \"PRAGMA foreign_key_check\")' $store/Migrator.swift && grep -qF 'guard violations.isEmpty else { throw ForeignKeyViolation(rows: violations.count) }' $store/Migrator.swift"
check "import accepts schema 1 up to the current schema (Q-063)" grep -qF 'guard (1...expected).contains(document.schemaVersion) else {' $store/Repository+Export.swift

# Docs (D9).
check "03 § Migrations: the FK-off path and migration 002" bash -c "grep -qF '**Migration 002 (\`002_providers.sql\`, Q-062):**' docs/03-data-model.md && grep -qF 'Every migration runs with \`PRAGMA foreign_keys = OFF\`' docs/03-data-model.md"
check "Q-063 is logged" grep -qF '## Q-063 Importing an export made by an earlier schema' docs/QUESTIONS.md
check "2.1's launch checks expect 001 and 002 on a fresh root" grep -qF '"from":1,"to":2' scripts/stages/2.1.sh

for suite in Migration002Tests MigrationTests ExportImportTests FixtureDBTests SmokeTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
