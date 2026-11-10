# Stage 3.3 — Provider seam & registry (14 § Stage 3.3). Sourced by scripts/verify-stage.sh.

prov=Sources/TokenBeCore/Providers
inventory=(
  $prov/ProviderID.swift $prov/Capabilities.swift $prov/ProviderAdapter.swift $prov/ProviderRegistry.swift
  $prov/Verified.swift scripts/record-fixtures.sh Tests/TokenBeCoreTests/ProviderIDTests.swift
  Tests/TokenBeCoreTests/VerifiedProvidersTests.swift scripts/stages/3.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done
check "record-fixtures.sh is executable" test -x scripts/record-fixtures.sh

check "ProviderID declared once, in Providers/ (moved from SettingSpec)" test "$(grep -rl 'enum ProviderID' Sources | tr -d '\n')" = "$prov/ProviderID.swift"
check "ProviderID has 03's five cases in 08's order" grep -qF 'case openai, anthropic, openrouter, deepseek, xai' $prov/ProviderID.swift
for field in 'usage: Bool' 'cost: Bool' 'balance: Bool' 'perKeyUsage: Bool' 'keyNames: Bool' \
             'balanceModeDefault: BalanceMode' 'usageLag: Duration' 'currencyHint: Currency'; do
  check "Capabilities has $field (14 step 2)" grep -qF "public var $field" $prov/Capabilities.swift
done
for method in 'func probe(key: String, transport: any HTTPTransport) async -> ProbeResult' \
              'func pollUsage(_ context: PollContext)' 'func pollCost(_ context: PollContext)' \
              'func pollBalance(_ context: PollContext)' 'func pollKeys(_ context: PollContext)'; do
  check "ProviderAdapter: $method" grep -qF "$method" $prov/ProviderAdapter.swift
done
check "Verified starts empty (D-verified-providers)" grep -qF 'public static let providers: Set<ProviderID> = []' $prov/Verified.swift
check "Release onboarding is limited to verified providers" grep -qF '(isDebug || verified.contains($0))' $prov/ProviderRegistry.swift

# 14 Verify: the recorder's offline self-test; its help names every key variable; it never reads .env.
check "record-fixtures.sh --self-test (14 Verify)" scripts/record-fixtures.sh --self-test
for var in OPENAI_ADMIN_KEY ANTHROPIC_ADMIN_KEY OPENROUTER_MANAGEMENT_KEY DEEPSEEK_API_KEY XAI_API_KEY; do
  check "record-fixtures.sh --help names $var" bash -c "scripts/record-fixtures.sh --help | grep -q $var"
done
check "record-fixtures.sh never reads .env" bash -c "! grep -nE '(source|\\.) +[^ ]*\\.env|cat +[^ ]*\\.env|< *[^ ]*\\.env' scripts/record-fixtures.sh"
check "record-fixtures.sh passes keys to curl on stdin, not argv" bash -c "grep -q -- '--config -' scripts/record-fixtures.sh && ! grep -nE 'curl [^|]*KEY_VALUE' scripts/record-fixtures.sh"
check "without a key it refuses and writes nothing" bash -c "env -u OPENAI_ADMIN_KEY scripts/record-fixtures.sh openai | grep -q 'set OPENAI_ADMIN_KEY' && [[ -z \"\$(git status --porcelain Tests/Fixtures/providers)\" ]]"
check "check-no-secrets.sh (no key-shaped literal in sources, tests or build products)" scripts/check-no-secrets.sh

for suite in ProviderIDTests CapabilitiesTests ProviderRegistryTests VerifiedProvidersTests FixtureDBTests; do
  check "suite $suite passed" suite_passed "$suite"
done
