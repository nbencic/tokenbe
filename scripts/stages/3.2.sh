# Stage 3.2 — Keychain seam (14 § Stage 3.2). Sourced by scripts/verify-stage.sh.

kc=Sources/TokenBeCore/Keychain
inventory=(
  $kc/KeyStore.swift $kc/KeychainKeyStore.swift Tests/TokenBeCoreTests/Support/InMemoryKeyStore.swift
  Tests/TokenBeCoreTests/KeyStoreTests.swift scripts/stages/3.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 2 as decided in Q-027: login keychain, generic password, the 04 service, ThisDeviceOnly, not synchronizable.
for attribute in 'kSecClassGenericPassword' 'service = "dev.bathyon.tokenbe"' 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' \
                 'kSecAttrSynchronizable as String] = false' 'kSecUseDataProtectionKeychain as String: false'; do
  check "KeychainKeyStore: $attribute" grep -qF "$attribute" $kc/KeychainKeyStore.swift
done
for evt in keychainReadFailed keychainWriteFailed keychainDeleteFailed keychainAccessDenied; do
  check "event .$evt emitted by KeychainKeyStore" grep -qF ".$evt" $kc/KeychainKeyStore.swift
done
check "SecItem calls only in KeychainKeyStore (R8)" bash -c "! grep -rlE 'SecItem(Add|Update|Delete|CopyMatching)' Sources | grep -v '$kc/KeychainKeyStore.swift'"
check "tests use only the .test service (never the owner's items)" bash -c "! grep -nE 'KeychainKeyStore\\((logPipeline:|\\))' Tests/TokenBeCoreTests/*.swift"
check "no secret ever passed to a log call in Keychain/" bash -c "! grep -nE '(emit|Log\\.[a-z]+)\\(.*secret' $kc/*.swift"
check "check-log-events.sh" scripts/check-log-events.sh

for suite in KeyStoreTests KeychainKeyStoreIntegrationTests; do
  check "suite $suite passed" suite_passed "$suite"
done
# The integration suite ran rather than being skipped (it is skipped only when the keychain is locked).
# A self-closing <testcase … /> has no <skipped/> or <failure> child; the old `grep -A2` read the NEXT test case's
# <skipped/> (FixtureDBTests.regenerate) once parallel order put it there (PM-3.4-6).
ran_integration() { grep -qE '<testcase classname="TokenBeCoreTests\.KeychainKeyStoreIntegrationTests" name="roundTrip\(\)"[^>]*/>' build/results/test-swift-testing.xml; }
check "KeychainKeyStoreIntegrationTests ran (not skipped)" ran_integration
leftover_test_items() { ! security find-generic-password -s dev.bathyon.tokenbe.test >/dev/null 2>&1; }
check "no item left under dev.bathyon.tokenbe.test" leftover_test_items
