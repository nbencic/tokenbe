# Stage 5.1 — Price book (14 § Stage 5.1). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
res=$app/Resources
inventory=(
  $core/Pricing/PriceFeedFetcher.swift $core/Pricing/PriceBook.swift $core/Pricing/PriceEntry.swift
  $core/Pricing/Lookup.swift $res/prices.bundled.json $res/prices.bundled.sha256 scripts/update-bundled-prices.sh
  $core/Store/Repository+Prices.swift $app/SettingsUI/PriceBookSection.swift $app/PriceBookModel.swift
  Tests/TokenBeCoreTests/PriceLookupTests.swift Tests/TokenBeCoreTests/PriceFeedTests.swift
  Tests/TokenBeUITests/PriceBookUITests.swift Tests/Fixtures/prices/litellm.snapshot.json scripts/stages/5.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 1: the bundled snapshot, chat entries only, with its sha256; the refresh script.
check "update-bundled-prices.sh is executable and keeps mode == chat" bash -c "test -x scripts/update-bundled-prices.sh && grep -qF '.value.mode == \"chat\"' scripts/update-bundled-prices.sh"
check "prices.bundled.json holds only chat entries" bash -c "jq -e 'length > 0 and all(.[]; .mode == \"chat\")' $res/prices.bundled.json"
check "prices.bundled.sha256 matches the file" bash -c "[[ \"\$(shasum -a 256 $res/prices.bundled.json | cut -d' ' -f1)\" == \"\$(tr -d '[:space:]' < $res/prices.bundled.sha256)\" ]]"
check "most chat entries are priced (O-6)" bash -c "jq -e '([.[] | select((.input_cost_per_token // 0) > 0)] | length) * 2 > length' $res/prices.bundled.json"
check "no key-shaped string in the bundled file" bash -c "d=\$(mktemp -d); cp $res/prices.bundled.json \"\$d/\"; scripts/check-no-secrets.sh --root \"\$d\"; s=\$?; rm -rf \"\$d\"; exit \$s"

# Step 2: startup step 4, after accounts, before the login item and the scheduler.
check "startup step 4 (prices) follows accounts (04)" bash -c "grep -A1 'StartupStep(\"accounts\")' $app/Startup.swift | grep -qF 'StartupStep(\"prices\")'"
check "StartupSequenceTests lists the prices step (D7)" grep -qF '"accounts", "prices", "scheduler"' Tests/TokenBeCoreTests/StartupSequenceTests.swift
check "the bundled seed is bundled-<appversion>, logged price.feed_ok source=bundled" bash -c "grep -qF '\"bundled-\\(appVersion)\"' $core/Pricing/PriceBook.swift && grep -qF '\"source\": \"bundled\"' $core/Pricing/PriceBook.swift"

# Step 3: the fetcher (02: If-None-Match, 10 s, 20 MB, sha256; O-6), prune to 4.
for literal in 'headers["If-None-Match"] = etag' 'timeout: TimeInterval = 10' 'maxBytes = 20 * 1024 * 1024' \
               'if sha == current?.sha256' 'if table.shapeChanged'; do
  check "fetcher: $literal" grep -qF "$literal" $core/Pricing/PriceFeedFetcher.swift
done
check "prunePriceSnapshots(keep: 4) after a new snapshot" bash -c "grep -qF 'keepSnapshots = 4' $core/Pricing/PriceBook.swift && grep -qF 'prunePriceSnapshots(keep: Self.keepSnapshots)' $core/Pricing/PriceBook.swift"
check "prune never deletes the current snapshot" grep -qF 'DELETE FROM price_snapshot WHERE is_current = 0' $core/Store/Repository+Prices.swift

# Step 4: lookup (05's 6 steps, V5) and the events.
check "V5: lookup returns nil for a zero or missing input/output rate" bash -c "grep -qF 'hit.entry.isPriced else { return nil }' $core/Pricing/Lookup.swift && grep -qF '(input ?? 0) > 0 && (output ?? 0) > 0' $core/Pricing/PriceEntry.swift"
for evt in priceFeedOk priceFeedFailed priceParseFailed priceStale priceOverrideSet; do
  check "event .$evt emitted by Pricing" grep -rqF ".$evt," $core/Pricing
done
check "check-log-events.sh (07 ↔ Evt)" scripts/check-log-events.sh
check "no price literal in Pricing (R2: prices come from the feed or overrides)" bash -c "! grep -nE '[0-9]e-0[0-9]' $core/Pricing/*.swift"

# Step 5: the daily step (its 04 position is checked by 4.3.sh's order check).
check "daily step price refresh runs the model's refresh" grep -qF 'DailyStep("price refresh") { _ in try await prices?.refresh() }' $app/DailyActivityRegistration.swift

# Step 6: UI. 09 keys consumed and controlled (D4); 08 copy (D8).
check "refresh reads tb.price.feedURL, feedEnabled and staleAfterDays" bash -c "for k in priceFeedURL priceFeedEnabled priceStaleAfterDays; do grep -qF \"settings.\$k\" $app/PriceBookModel.swift || exit 1; done"
check "Sources: feed toggle and Stale after stepper" bash -c "grep -qF 'isOn: \$settings.priceFeedEnabled' $app/SettingsUI/PriceBookSection.swift && grep -qF 'value: \$settings.priceStaleAfterDays' $app/SettingsUI/PriceBookSection.swift"
check "Advanced: the feed URL field (09: editable in Advanced only)" bash -c "grep -qF 'PriceFeedURLField(settings: settings)' $app/SettingsUI/AdvancedTab.swift && grep -qF 'settings.priceFeedURL = ' $app/SettingsUI/AdvancedTab.swift"
check "Sources tab shows the Price book group" grep -qF 'PriceBookSection(settings: settings, prices: prices)' $app/SettingsUI/SourcesTab.swift
check "account page shows the Prices chip" grep -qF 'prices: model.environment?.prices?.status' $app/Dashboard/AccountDetailView.swift
for copy in 'Price book' 'Refresh now' 'Reset to feed' 'Prices'; do
  check "Strings has copy: $copy" grep -qF "\"$copy\"" $app/Strings.swift
done

for suite in PriceLookupTests PriceFeedTests FormattersTests StartupSequenceTests; do
  check "suite $suite passed" suite_passed "$suite"
done
# 14 Verify: first launch logs price.feed_ok source=bundled and price_snapshot has one row (asserted by the UI test
# against its test root's log and database); + adds an override row; Reset to feed removes it.
check "the UI test asserts 14's Verify lines" bash -c "grep -qF 'first launch logs price.feed_ok source=bundled' Tests/TokenBeUITests/PriceBookUITests.swift && grep -qF 'XCTAssertEqual(try count(\"SELECT count(*) FROM price_snapshot\"), 1)' Tests/TokenBeUITests/PriceBookUITests.swift"
ui_check "PriceBookUITests passed" grep -q "Test Suite 'PriceBookUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
