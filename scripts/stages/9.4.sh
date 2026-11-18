# Stage 9.4 — Update check (14 § Stage 9.4, 02 § Update check, 09 tb.update.*, D-no-sparkle). Sourced by
# scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Update/UpdateChecker.swift $app/Update/UpdateModel.swift $app/Components/UpdateBadge.swift
  Tests/TokenBeCoreTests/UpdateCheckerTests.swift Tests/TokenBeUITests/UpdateCheckUITests.swift scripts/stages/9.4.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 02: one GET to GitHub's latest release; tag_name vs the bundle; no download, no install.
check "02's endpoint, the one GitHub API URL" bash -c "grep -qF 'URL(string: \"https://api.github.com/repos/nbencic/tokenbe/releases/latest\")' $core/Update/UpdateChecker.swift && test \$(grep -rhoF 'api.github.com' Sources | wc -l) -eq 1"
check "semver with the v prefix stripped; unparsable shows nothing" bash -c "grep -qF 'if body.first == \"v\" || body.first == \"V\" { body = body.dropFirst() }' $core/Update/UpdateChecker.swift && grep -qF 'guard let latest = SemVer(latestSeen), let bundle = SemVer(current), latest > bundle else { return false }' $core/Update/UpdateChecker.swift"
check "the skipped version hides the badge (09 ignoredVersion)" grep -qF 'return SemVer(ignored) != latest' $core/Update/UpdateChecker.swift
check "update.check_ok {latest, current, newer} and update.check_failed (07)" bash -c "grep -qF '.info, .updateCheckOk, cat: .update' $core/Update/UpdateChecker.swift && grep -qF '\"latest\": .string(latest.description), \"current\": .string(current), \"newer\": .bool(newer)' $core/Update/UpdateChecker.swift && grep -qF '.warn, .updateCheckFailed, cat: .update' $core/Update/UpdateChecker.swift"
check "no download or install (D-no-sparkle)" bash -c "! grep -rnE 'downloadTask|URLSessionDownload|Sparkle|installer|hdiutil' $core/Update $app/Update"
check "one GET per UTC day while checks are on (08's caption)" bash -c "grep -qF 'guard settings.updateCheckEnabled,' $app/Update/UpdateModel.swift && grep -qF 'UpdateChecker.isDue(lastCheckedAt: settings.updateLastCheckedAt, now: now) else { return }' $app/Update/UpdateModel.swift"
check "the check writes tb.update.lastCheckedAt and latestSeen; Skip writes ignoredVersion (D4)" bash -c "grep -qF 'settings.updateLastCheckedAt = now.timeIntervalSince1970' $app/Update/UpdateModel.swift && grep -qF 'settings.updateLatestSeen = latest' $app/Update/UpdateModel.swift && grep -qF 'settings.updateIgnoredVersion = settings.updateLatestSeen' $app/Update/UpdateModel.swift"
check "the daily step sits after the price refresh (04, PM-4.3-3)" grep -qF 'DailyStep("update check") { _ in await updates?.check() }' $app/DailyActivityRegistration.swift

# 08 § Privacy and the badge's three places (02, 09, 14 § 9.4).
check "Strings has 08's row and caption" bash -c "grep -qF 'checkForUpdatesDaily = \"Check for updates daily\"' $app/Strings.swift && grep -qF 'or the release page \\u{2014} no in-app updater in v1.\"' $app/Strings.swift && grep -qF 'updateAvailable = \"Update available\"' $app/Strings.swift && grep -qF 'skipThisVersion = \"Skip this version\"' $app/Strings.swift"
check "Privacy's toggle binds tb.update.checkEnabled" grep -qF 'Toggle(isOn: $settings.updateCheckEnabled) {' $app/SettingsUI/PrivacyTab.swift
check "the badge in Privacy, the Overview and above the popover footer" bash -c "grep -qF 'UpdateBadge(updates: updates, place: \"settings.privacy\")' $app/SettingsUI/PrivacyTab.swift && grep -qF 'UpdateBadge(updates: model.environment?.updates, place: \"dashboard.overview\")' $app/Dashboard/OverviewView.swift && grep -qF 'UpdateBadge(updates: model.environment?.updates, place: \"popover\")' $app/Popover/PopoverView.swift"
check "an html_url is opened only when it is a TokenBe release page" grep -qF 'text.hasPrefix(prefix + "/")' $core/Update/UpdateChecker.swift
check "1.3.sh no longer guards Check for updates (PM-8.3-1)" bash -c "! grep -qE '^for later in .*\"Check for updates\"' scripts/stages/1.3.sh"

for suite in UpdateCheckerTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "UpdateCheckUITests passed (the badge, the toggle, Skip)" grep -q "Test Suite 'UpdateCheckUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
