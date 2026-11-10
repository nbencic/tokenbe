# Postmortem — Stage 3.2 Keychain seam
Date: 2026-11-10 · Branch: s3.2-keychain · PR: #12 · Planned size: S · Commits: 4

## Outcome
API keys now have a place to live. Nothing is visible to the user yet.
- **`KeyStore`** (14 § 0.3) has `get`, `set` and `delete` by `keychain_ref`, `async throws(KeyStoreError)`, and states the R8 usage contract: register with the `Redactor` for the request, unregister in a `defer`.
- **`KeychainKeyStore`** writes one `kSecClassGenericPassword` item per account:
  - service `dev.bathyon.tokenbe`, account = the ref;
  - `WhenUnlockedThisDeviceOnly`, never synchronizable;
  - on the **login keychain**, by the owner's decision (Q-027). 14's data-protection keychain cannot be written by ad-hoc-signed builds.
- **Logging.** Every failing `OSStatus` logs `keychain.read_failed` / `write_failed` / `delete_failed` at error, or `keychain.access_denied` at fault for `errSecInteractionNotAllowed` / `errSecAuthFailed`. Records carry `acct` and `osstatus`, never the secret.
- **`InMemoryKeyStore`** is the test double, with injectable failures.
- **Verification.** 168 Core tests pass, 5 of them new. `KeychainKeyStoreIntegrationTests` (tag `.keychainIntegration`) ran against the real login keychain under `dev.bathyon.tokenbe.test` only: write, read, overwrite, delete, the attributes, and no synchronizable copy. It left no item behind.

DoD D1–D3, D9 and D11 are met; D12 by the PR's CI; D13 by this file.

## What went as planned
- The spike came first (PM-1.3-1). It found the `-34018` blocker in two tool calls, before any `KeychainKeyStore` code existed. The owner was asked once with three concrete options, and the work that did not depend on the answer (the protocol and the in-memory store) was done before asking.
- A second spike showed which attributes the login keychain reports back: `class`, `svce`, `acct`, `labl`, dates and data, but not `pdmn` or `sync`. SEC-2's test was written against what is observable, not against a guess.
- Full Core suite looped 50 times (PM-1.2-3), with the real-keychain integration test included: 50 of 50 passed, and no test item was left behind.
- The Release build with warnings as errors (the Swift 6.1 gate) and `check-no-secrets.sh` passed on the first run.

## What went wrong
1. **14 § Stage 3.2 step 2 could not work on any build before H4.** `kSecUseDataProtectionKeychain = true` needs an entitlement that only a team-signed, provisioned build has. TokenBe stays ad-hoc signed until 11.5 (H1 was retired, and PM-0.1-3 moved the Apple ID to 11.5). Root cause: the plan's two review passes did not check signing prerequisites for Security-framework flags. Fix: the owner chose the login keychain (Q-027), and 13, 11 and 14 are updated. Cost: two spikes and one owner question.
2. **Two SwiftLint `large_tuple` violations**, from a four-member tuple binding in `report(_:_:)` and a tuple-typed test table. They became separate `switch` expressions and a small struct. Lint ran standalone before verify (PM-1.3-5), so no verify run was lost.

## Verify and CI failures
- Verify run 1: `STAGE 3.2 OK`, 477 checks across stages 0.1–3.2 and D13, the UI suites included. It passed on the first run, under `caffeinate -i -d` (PM-3.1-5).
- CI: PR #12 `build-test` passed on the first run (5 m 59 s). `KeychainKeyStoreIntegrationTests` ran and passed on the GitHub runner's login keychain too, in 0.47 s, so it was not skipped.

## Deviations from the docs
- 14 § Stage 3.2 step 2: `kSecUseDataProtectionKeychain = true` → `false`, the login keychain (owner, Q-027). 14, 11 SEC-2 and 13 D-keychain-only are updated.
- 14 inventory: `Tests/Support/InMemoryKeyStore.swift` → `Tests/TokenBeCoreTests/Support/`.
- 14 Tests: the integration test is skipped when the keychain cannot be written without interaction (a probe write), which covers a locked keychain and a headless session alike.

## Judgment calls
- Q-027 (Blocking: yes, answered by the owner): the login keychain. Also: the error type, `errSecDecode` for non-UTF-8 items, `errSecUserCanceled` as a plain failure, update-or-add for `set`, idempotent `delete`, and what the log records carry.

## Carry-forward actions
- PM-3.2-1 · agent · 3.5 · Onboarding is the first caller of `KeyStore.set`. The UI tests must inject `InMemoryKeyStore` (or `KeychainKeyStore(service: "dev.bathyon.tokenbe.test")`) under `TOKENBE_TEST_ROOT`. A Debug UI run must never write to the owner's `dev.bathyon.tokenbe` items.
- PM-3.2-2 · agent · 3.5 · Startup step 3 (04): read each account's item. A missing item logs `keychain.missing` and sets the account to `needs_key`, and `StartupSequenceTests` gains the step.
- PM-3.2-3 · agent · 11.2 · Security review: re-assess Q-027 once Developer ID signing exists (H4). If moving to the data-protection keychain is worth a one-time migration of existing items, log it as a new Q.
- PM-3.2-4 · agent · process · Before implementing any Security- or entitlement-gated API, spike it on an ad-hoc-signed binary first.
- Earlier actions targeting 3.2: none.
