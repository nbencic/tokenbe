# Stage 5.3 — Ledger, runway, bands; Alerts tab; cards and Overview complete (14 § Stage 5.3). Sourced by
# scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Ledger/Spend.swift $core/Ledger/Burn.swift $core/Ledger/Remaining.swift $core/Ledger/EstimateBand.swift
  $core/Ledger/Runway.swift $core/Ledger/BandEvaluator.swift $core/Presentation/AccountPresentation.swift
  $core/Store/Repository+Ledger.swift $core/Store/Repository+Band.swift
  $app/Dashboard/SetAnchorSheet.swift $app/Dashboard/AddTopUpSheet.swift $app/Dashboard/LedgerList.swift
  $app/Dashboard/RunwayBoard.swift $app/Dashboard/OverviewHeadline.swift $app/Popover/AlertBanner.swift
  $app/Popover/AccountCardView.swift $app/SettingsUI/AlertsTab.swift scripts/check-traceability.sh
  Tests/Fixtures/expected/ledger.csv Tests/Fixtures/logs/traceability.ok.ndjson
  Tests/Fixtures/logs/traceability.bad.ndjson Tests/TokenBeCoreTests/LedgerTests.swift
  Tests/TokenBeCoreTests/BurnTests.swift Tests/TokenBeCoreTests/BandTransitionTests.swift
  Tests/TokenBeUITests/AnchorRunwayUITests.swift scripts/stages/5.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 1: 05's formulas.
check "burn_7d needs 2 closed days; burn_today gates 7200 s and 100 cents" bash -c "grep -qF 'minimumClosedDays = 2' $core/Ledger/Burn.swift && grep -qF 'minimumSecondsToday: Int64 = 7200' $core/Ledger/Burn.swift && grep -qF 'minimumCentsToday: Int64 = 100' $core/Ledger/Burn.swift"
check "burn and spend since anchor use the one daily rule (PM-5.2-1)" bash -c "grep -qF 'Spend.daily(summary' $core/Ledger/AccountSummaryBuilder.swift && grep -qF 'daily(account, today: today, inputs: inputs).filter' $core/Ledger/Spend.swift"
check "M: 3 % drift, lag, unpriced, age factor in halves" bash -c "grep -qF 'divideUp(max(0, inputs.spendSinceAnchor) * 3, by: 100)' $core/Ledger/EstimateBand.swift && grep -qF '(2 + steps), by: 2)' $core/Ledger/EstimateBand.swift"
check "band order: unknown, critical, low, watch, healthy (05)" bash -c "awk '/return \(\.unknown/{u=NR} /return \(\.critical/{c=NR} /return \(\.low/{l=NR} /return \(\.watch, false\) }/{w=NR} /return \(\.healthy/{h=NR} END{exit !(u<c && c<l && l<w && w<h)}' $core/Ledger/BandEvaluator.swift"
check "no Double in money code (R7)" bash -c "! grep -nE 'Double|Float' $core/Ledger/Burn.swift $core/Ledger/Remaining.swift $core/Ledger/EstimateBand.swift $core/Ledger/Spend.swift"
check "ledger.csv has 16 cases" bash -c "[[ \$(tail -n +2 Tests/Fixtures/expected/ledger.csv | grep -c .) == 16 ]]"

# Step 2: band_state with inputs_json in one statement (V6), logged only on change.
check "recordBand is one INSERT OR REPLACE (V6)" grep -qF 'try state.insert(db, onConflict: .replace)' $core/Store/Repository+Band.swift
check "ui.band_change only after a successful write" bash -c "awk '/recordBand\(BandStateRecord/{w=NR} /\.uiBandChange/{l=NR} END{exit !(w && l && w<l)}' $core/Ledger/BandEvaluator.swift"
check "the app records bands after each rebuild" grep -qF 'await bands.record(evaluated, persisted: persisted, trigger: trigger, now: now)' $app/AppModel.swift

# Step 3: sheets, ledger list, header buttons; system rows are never deleted (R7).
check "deleteUserLedgerEvent deletes user rows only, in SQL" grep -qF "DELETE FROM ledger_event WHERE id = ? AND source = 'user'" $core/Store/Repository+Ledger.swift
check "ledger.topup and ledger.anchor_set emitted" bash -c "grep -qF '.ledgerAnchorSet : .ledgerTopup' $core/Accounts/AccountLifecycle.swift"
check "account page: Set anchor…, Add top-up…, Refresh, ledger" bash -c "for id in dashboard.account.setAnchor dashboard.account.addTopUp dashboard.account.refresh; do grep -qF \"\\\"\$id\\\"\" $app/Dashboard/AccountDetailView.swift || exit 1; done; grep -qF 'LedgerList(events:' $app/Dashboard/AccountDetailView.swift"
check "the anchor sheet cannot date the future and caps the note at 140" bash -c "grep -qF 'in: ...Date()' $app/Dashboard/SetAnchorSheet.swift && grep -qF 'noteLimit = 140' $core/Accounts/AccountLifecycle.swift"

# Step 4: cards, banner, keyboard.
check "popover shows the alert banner" grep -qF 'AlertBannerPick.pick(model.sortedAccounts)' $app/Popover/PopoverView.swift
check "↑/↓/⏎ move and open cards" bash -c "grep -qF '.onKeyPress(.downArrow)' $app/Popover/PopoverView.swift && grep -qF '.onKeyPress(.upArrow)' $app/Popover/PopoverView.swift && grep -qF '.onKeyPress(.return)' $app/Popover/PopoverView.swift"
check "unknown sorts last in runway order (08)" grep -qF '$0.band == .unknown ? nil : $0.runwayMin' $core/Presentation/AccountOrder.swift

# Step 5: Overview.
check "Overview: headline and runway board" bash -c "grep -qF 'OverviewHeadline(accounts:' $app/Dashboard/OverviewView.swift && grep -qF 'RunwayBoard(model: model' $app/Dashboard/OverviewView.swift"

# Steps 6–7: Alerts tab (D4: every 5.3 key has a control and a consumer) and auto-reload.
for key in alertsWatchDays alertsLowDays alertsCriticalDays alertsDollarFloorCents alertsStaleMultiplier \
           alertsDriftThresholdPct alertsAnchorAgeDays; do
  check "Alerts tab controls $key" grep -qF "\$settings.$key" $app/SettingsUI/AlertsTab.swift
done
check "band thresholds read the Alerts settings" grep -qF 'watchDays: settings.alertsWatchDays' $core/Ledger/BandEvaluator.swift
check "Settings tabs in 08's order (Alerts between Sources and Privacy)" bash -c "awk '/SettingsTab.sources/{s=NR} /SettingsTab.alerts/{a=NR} /SettingsTab.privacy/{p=NR} END{exit !(s<a && a<p)}' $app/SettingsUI/SettingsView.swift"
check "Accounts: auto-reload toggle, below and adds (anchored only)" bash -c "grep -qF 'settings.accounts.autoReload\"' $app/SettingsUI/AccountsTab.swift && grep -qF 'autoReloadBelowCents = below' $app/SettingsUI/AccountsTab.swift"
for copy in 'Collecting\u{2026} runway after 2 days of data' 'Add top-up\u{2026}' 'Alerts' 'Shortest runway: '; do
  check "Strings has copy: $copy" grep -qF "\"$copy" $app/Strings.swift
done

# E2E-9: the traceability script passes a traced log and fails an untraced one (the real run is 5.5's, Q-041).
check "check-traceability.sh passes a traced log" scripts/check-traceability.sh Tests/Fixtures/logs/traceability.ok.ndjson
check "check-traceability.sh fails an untraced log" bash -c "! scripts/check-traceability.sh Tests/Fixtures/logs/traceability.bad.ndjson"
check "check-log-events.sh (07 ↔ Evt)" scripts/check-log-events.sh

for suite in LedgerTests BurnTests BandTransitionTests AccountPresentationTests AccountOrderTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing, Q-041)" scripts/run.sh build-uitest
ui_check "AnchorRunwayUITests passed" grep -q "Test Suite 'AnchorRunwayUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "AnchorRunwayUITests asserts E2E-9 on its own log" grep -qF 'XCTAssertEqual(try untracedBandChanges(), []' Tests/TokenBeUITests/AnchorRunwayUITests.swift
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
