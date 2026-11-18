# Stage 9.1 — Retention roll-ups (14 § Stage 9.1, 03 § Retention tiers). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Store/Rollup.swift Tests/TokenBeCoreTests/RetentionTests.swift scripts/stages/9.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# The daily step at 04's position, with 09's two windows read when it runs.
rollup_order() {
  local f=$app/DailyActivityRegistration.swift m r p
  m="$(grep -n 'DailyStep("model drift")' $f | cut -d: -f1)"; r="$(grep -n 'DailyStep("roll-ups")' $f | cut -d: -f1)"
  p="$(grep -n 'DailyStep("price refresh")' $f | cut -d: -f1)"
  [[ -n "$m" && -n "$r" && -n "$p" && "$m" -lt "$r" && "$r" -lt "$p" ]]
}
check "roll-ups run after the model drift, before the price refresh (04)" rollup_order
check "the step reads tb.retention.hourlyDays and tb.retention.rawHarnessDays (D4)" grep -qF 'RetentionPolicy(hourlyDays: settings.retentionHourlyDays, rawHarnessDays: settings.retentionRawHarnessDays)' $app/DailyActivityRegistration.swift
check "03's fixed windows: monthly after 400 d, balance at full rate for 7 d" bash -c "grep -qF 'static let monthlyAfterDays = 400' $core/Store/Rollup.swift && grep -qF 'static let balanceFullRateDays = 7' $core/Store/Rollup.swift"

# 03 § Retention tiers, one transaction per tier per account (R7), idempotent on the bucket keys.
check "hourly provider rows become rollup; harness rows keep harness (Q-055)" grep -qF "CASE source WHEN 'harness' THEN 'harness' ELSE 'rollup' END" $core/Store/Rollup.swift
check "an anchor's day stays hourly (05 spend_since_anchor, Q-055)" grep -qF "SELECT substr(ts, 1, 10) FROM ledger_event WHERE account_id = ? AND kind = 'anchor'" $core/Store/Rollup.swift
check "monthly rows are recomputed, written only when they change" bash -c "grep -qF \"'1mo', model, provider_key_id\" $core/Store/Rollup.swift && grep -qF 'WHERE \\(differs)' $core/Store/Rollup.swift"
check "each tier is its own write per account" bash -c "for op in rollupHourly rollupMonthly purgeHarnessEvents thinBalanceSnapshots; do grep -qF \"database.write(\\\"\$op\\\")\" $core/Store/Rollup.swift || exit 1; done"
check "the purge follows the roll-ups in one throwing run" bash -c "h=\$(grep -n 'store.rollupHourly(accountID' $core/Store/Rollup.swift | head -n 1 | cut -d: -f1); p=\$(grep -n 'store.purgeHarnessEvents(before' $core/Store/Rollup.swift | cut -d: -f1); [[ -n \"\$h\" && -n \"\$p\" && \"\$h\" -lt \"\$p\" ]]"
check "thinning keeps each day's first and last snapshot per currency (Q-055)" bash -c "grep -qF 'SELECT MIN(ts), currency' $core/Store/Rollup.swift && grep -qF 'UNION SELECT MAX(ts), currency' $core/Store/Rollup.swift"
check "db.rollup {tier, rows_in, rows_out} (07)" bash -c "grep -qF '.dbRollup, cat: .db' $core/Store/Rollup.swift && grep -qF '\"rows_in\": .int(count.rowsIn), \"rows_out\": .int(count.rowsOut)' $core/Store/Rollup.swift"
check "Repository composes RetentionRepository" grep -qF '& IngestRepository & RetentionRepository' $core/Store/Repository.swift

# Readers: monthly rows sit alongside the daily ones, so every usage read skips them.
skip_monthly() {
  local f n m
  for f in $core/Store/Observation.swift $core/Ledger/Attribution.swift $core/Ledger/Drift.swift; do
    n="$(grep -c 'FROM usage_bucket' $f)"; m="$(grep -c "bucket_width <> '1mo'" $f)"
    [[ "$n" -ge 1 && "$n" == "$m" ]] || { echo "$f: $n reads, $m skip 1mo"; return 1; }
  done
}
check "every summary read of usage_bucket skips 1mo rows" skip_monthly
check "Anthropic's cache savings count rollup rows (PM-8.2-4)" grep -qF 'case .anthropic: .success(["provider", "rollup"])' $core/Ledger/CacheSavings.swift
check "a purged harness day is not inferred and goes to the single app (PM-7.2-1)" bash -c "grep -qF '.union(harnessBucketDays(account.id, inputs: inputs))' $core/Ledger/Attribution+Harness.swift && grep -qF 'let app = reported.contains(day) ? onlyApp : nil' $core/Ledger/Attribution+Harness.swift"

# Advanced → the two retention steppers (14 § 9.1 Adds; 09 bounds).
check "Strings has the retention copy" bash -c "grep -qF '\"Hourly detail kept for\"' $app/Strings.swift && grep -qF '\"Raw harness events kept for\"' $app/Strings.swift"
check "Advanced binds both steppers to their keys within 09's bounds" bash -c "grep -qF 'Stepper(value: \$settings.retentionHourlyDays, in: SettingsKey.retentionHourlyDays.spec.intBounds' $app/SettingsUI/AdvancedTab.swift && grep -qF 'Stepper(value: \$settings.retentionRawHarnessDays,' $app/SettingsUI/AdvancedTab.swift && grep -qF 'in: SettingsKey.retentionRawHarnessDays.spec.intBounds' $app/SettingsUI/AdvancedTab.swift"
check "09's defaults and ranges: 90 d in 30–730 and 7–730" bash -c "grep -qF 'case .retentionHourlyDays: SettingSpec(type: .int, defaultValue: .int(90), rule: .intRange(30...730), tab: .advanced)' $core/Settings/SettingsKey.swift && grep -qF 'case .retentionRawHarnessDays: SettingSpec(type: .int, defaultValue: .int(90), rule: .intRange(7...730), tab: .advanced)' $core/Settings/SettingsKey.swift"
check "03 states the first and last snapshot and the harness roll-up source" bash -c "grep -qF 'first and last snapshot of each UTC day' docs/03-data-model.md && grep -qF \"harness rows keep \\\`source='harness'\\\`\" docs/03-data-model.md"

for suite in RetentionTests CacheSavingsTests AttributionTests ObservationTests DriftTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "AdvancedMaintenanceUITests passed (the retention steppers)" grep -q "Test Suite 'AdvancedMaintenanceUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
