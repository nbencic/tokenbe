# Stage 3.5 — Onboarding, Accounts tab, first account (14 § Stage 3.5). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $app/Onboarding/OnboardingSheet.swift $app/Onboarding/Step1Provider.swift $app/Onboarding/Step2Key.swift
  $app/Onboarding/Step3Result.swift $app/SettingsUI/AccountsTab.swift $app/Dashboard/SidebarView.swift
  $app/Popover/AccountCardView.swift $core/Store/Repository+Ledger.swift $core/Accounts/AccountLifecycle.swift
  $core/Keychain/FileKeyStore.swift $app/Components/ProviderGlyph.swift
  Tests/TokenBeUITests/OnboardingUITests.swift Tests/TokenBeCoreTests/AccountLifecycleTests.swift scripts/stages/3.5.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 08's copy, verbatim in Strings.swift (R9, D8).
for copy in 'Add account\u{2026}' 'Admin key required' 'Needs an Organization' 'Management key' \
            'Balance only \u{00B7} apps via harness' 'Added' 'Paste' 'Test & continue' 'Set anchor\u{2026}' \
            'Skip for now' 'Launch at login' 'Done' 'Key missing \u{00B7} Fix\u{2026}' 'Replace key\u{2026}' 'Test' \
            'Remove account\u{2026}' 'Keys & apps' 'Paused' 'No data yet' \
            'This looks like a project key. TokenBe needs an Admin key (sk-admin-\u{2026}).'; do
  check "Strings has 08 copy: $copy" grep -qF "\"$copy\"" $app/Strings.swift
done
check "Valid · tested <freshness> (08)" grep -qF '"Valid \u{00B7} tested \(freshness)"' $app/Strings.swift
check "no inline Text copy in views (D8)" bash -c "! grep -rnE 'Text\\(\"[A-Za-z]' $app --include=*.swift | grep -v Strings.swift"

# Step 1: onboarding is a 520×440 window (Q-030); tiles come from the registry; the key is stored only after a passed probe.
check "onboarding is 520×440 (08)" grep -qF 'CGSize(width: 520, height: 440)' $app/Onboarding/OnboardingSheet.swift
check "tiles come from registry.availableForOnboarding" grep -qF 'registry.availableForOnboarding' $app/Onboarding/OnboardingSheet.swift
check "added providers are disabled with Added" grep -qF 'Strings.added' $app/Onboarding/Step1Provider.swift
key_after_probe() {
  local probe create
  probe="$(grep -n 'lifecycle.probe(provider, key: key)' $app/Onboarding/OnboardingSheet.swift | head -n 1 | cut -d: -f1)"
  create="$(grep -n 'lifecycle.create(provider' $app/Onboarding/OnboardingSheet.swift | head -n 1 | cut -d: -f1)"
  [[ -n "$probe" && -n "$create" && "$probe" -lt "$create" ]] && grep -qF 'if let message = probe.humanMessage { return message }' $app/Onboarding/OnboardingSheet.swift
}
check "the Keychain write follows a passed probe (08, R8)" key_after_probe
check "the probe has a 10 s timeout on the injected clock" grep -qF 'probeTimeout = Duration.seconds(10)' $core/Accounts/AccountLifecycle.swift
check "create rolls back the Keychain item when the database refuses" grep -qF 'try await keyStore.delete(account.keychainRef)' $core/Accounts/AccountLifecycle.swift
check "onboarding marks tb.ui.onboardingDone" grep -qF 'settings.uiOnboardingDone = true' $app/Onboarding/OnboardingSheet.swift
check "Done runs the first keys and usage polls" bash -c "grep -qF 'job: .keys' $app/Onboarding/OnboardingSheet.swift && grep -qF 'job: .usage' $app/Onboarding/OnboardingSheet.swift"
check "the anchor is ledger_event(kind=anchor) with ledger.anchor_set" bash -c "grep -qF 'kind: \"anchor\"' $core/Accounts/AccountLifecycle.swift && grep -qF '.ledgerAnchorSet' $core/Accounts/AccountLifecycle.swift"
check "Repository includes LedgerRepository" grep -qF '& LedgerRepository' $core/Store/Repository.swift

# Step 2: the Accounts tab; remove cleans the Keychain item and templated settings (09).
for literal in 'Strings.replaceKey' 'Strings.test' 'Strings.removeAccount' 'Strings.paused' 'Strings.keysAndApps' \
               'repository.updateAccount' 'lifecycle.remove(' 'lifecycle.test(' 'lifecycle.replaceKey('; do
  check "AccountsTab: $literal" grep -qF "$literal" $app/SettingsUI/AccountsTab.swift
done
check "remove drops the templated settings" grep -qF 'settings.removeProviderKeys(provider)' $core/Accounts/AccountLifecycle.swift

# Step 3: startup step 3 checks existence only (R8) and logs keychain.missing.
check "startup runs the accounts step after the database" bash -c "grep -A1 'StartupStep(\"database\")' $app/Startup.swift | grep -qF 'StartupStep(\"accounts\")'"
check "StartupSequenceTests lists the accounts step (D7)" grep -qF '"logging", "database", "accounts"' Tests/TokenBeCoreTests/StartupSequenceTests.swift
check "step 3 uses KeyStore.contains, never get" bash -c "grep -A8 'func missingKeys' $core/Accounts/AccountLifecycle.swift | grep -qF 'keyStore.contains' && ! grep -A8 'func missingKeys' $core/Accounts/AccountLifecycle.swift | grep -qF 'keyStore.get'"
check "keychain.missing is logged" grep -qF '.keychainMissing' $core/Accounts/AccountLifecycle.swift

# PM-3.2-1: UI tests never use a keychain; the file store is DEBUG-only and bound to the test root.
check "FileKeyStore is DEBUG-only" bash -c "head -n 1 $core/Keychain/FileKeyStore.swift | grep -qx '#if DEBUG'"
check "the file store is used only under TOKENBE_TEST_ROOT" grep -qF 'if let root = paths.testRoot { return FileKeyStore(directory: root) }' $app/Startup.swift
check "fixture cases only under a DEBUG test root (PM-3.4-1)" grep -qF 'TOKENBE_TEST_FIXTURE_CASES' $app/Startup.swift

check "check-log-events.sh" scripts/check-log-events.sh
for suite in AccountLifecycleTests AccountSupportTests StartupSequenceTests KeyStoreTests ObservationTests \
             AccountSummaryBuilderTests OpenAITests; do
  check "suite $suite passed" suite_passed "$suite"
done
# 14 Verify: the UI test asserts 1 account, 4 poll_state rows and the provider keys in its own root (Q-025, Q-030).
check "OnboardingUITests passed" grep -q "Test Suite 'OnboardingUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
