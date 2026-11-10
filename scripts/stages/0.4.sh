# Stage 0.4 — App project, build configuration, first launch (14 § Stage 0.4). Sourced by scripts/verify-stage.sh.
# Every launch uses a throwaway TOKENBE_TEST_ROOT (Debug only, Q-014), so the owner's real logs, sentinel and
# settings are never read, written or deleted by verification.

verify_started="$(mktemp)"
inventory=(
  Config/Base.xcconfig Config/Debug.xcconfig Config/Release.xcconfig Config/Project.xcconfig Config/UITests.xcconfig
  TokenBe.xcodeproj/project.pbxproj TokenBe.xcodeproj/xcshareddata/xcschemes/TokenBe.xcscheme
  Sources/TokenBeApp/TokenBeApp.swift Sources/TokenBeApp/AppDelegate.swift Sources/TokenBeApp/Startup.swift
  Sources/TokenBeApp/Strings.swift Sources/TokenBeApp/Components/MenuBarGlyph.swift
  Sources/TokenBeApp/TokenBe.entitlements Sources/TokenBeApp/Resources/Assets.xcassets/Contents.json
  Sources/TokenBeApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
  Sources/TokenBeApp/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
  Sources/TokenBeCore/Startup/StartupSequence.swift Tests/TokenBeCoreTests/StartupSequenceTests.swift
  Tests/TokenBeUITests/LaunchSmokeTests.swift scripts/make-icon.swift scripts/stages/0.4.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done
for color in Ground Window Label AccentColor HealthHealthy HealthWatch HealthLow HealthCritical HealthUnknown \
  ClassInput ClassCacheWrite ClassCacheRead ClassOutput ClassReasoning; do
  check "color set $color (08)" test -s "Sources/TokenBeApp/Resources/Assets.xcassets/$color.colorset/Contents.json"
done

# D-xcconfig: project.pbxproj carries no build settings at all.
pbxproj_settings_empty() { ! grep -A1 "buildSettings = {" TokenBe.xcodeproj/project.pbxproj | grep -vE 'buildSettings = \{|^[[:space:]]*\};$|^--$'; }
check "project.pbxproj has no build settings (D-xcconfig)" pbxproj_settings_empty
check "project.pbxproj parses" plutil -lint TokenBe.xcodeproj/project.pbxproj

setting() { # setting <configuration> <name>
  xcodebuild -project TokenBe.xcodeproj -target TokenBe -configuration "$1" -showBuildSettings 2>/dev/null \
    | awk -v key="$2" '$1 == key && $2 == "=" { $1 = ""; $2 = ""; sub(/^  /, ""); print; exit }'
}
expect_setting() { [[ "$(setting "$1" "$2")" == "$3" ]] || { echo "$1 $2 = '$(setting "$1" "$2")', want '$3'"; return 1; }; }
for config in Debug Release; do
  check "$config bundle id" expect_setting "$config" PRODUCT_BUNDLE_IDENTIFIER dev.bathyon.tokenbe
  check "$config deployment target 15.0" expect_setting "$config" MACOSX_DEPLOYMENT_TARGET 15.0
  check "$config Swift 6.0" expect_setting "$config" SWIFT_VERSION 6.0
  check "$config strict concurrency complete" expect_setting "$config" SWIFT_STRICT_CONCURRENCY complete
  check "$config LSUIElement" expect_setting "$config" INFOPLIST_KEY_LSUIElement YES
  check "$config App Sandbox off (D-sandbox)" expect_setting "$config" ENABLE_APP_SANDBOX NO
  check "$config hardened runtime on" expect_setting "$config" ENABLE_HARDENED_RUNTIME YES
done

check "build-app (Debug)" scripts/run.sh build-app
check "build-app-release (Release, unsigned as in CI)" scripts/run.sh build-app-release

APP="build/DerivedData/Build/Products/Debug/TokenBe.app"
launch_cycle() { # launch_cycle <root> [kill]: launch, wait for app.launch, then quit (or kill -9)
  local root="$1" logs="$1/Logs/TokenBe" before i
  before="$(cat "$logs"/tokenbe-*.ndjson 2>/dev/null | grep -c '"evt":"app.launch"')"
  open -n --env "TOKENBE_TEST_ROOT=$root" "$APP" || return 1
  for i in $(seq 1 60); do
    [[ "$(cat "$logs"/tokenbe-*.ndjson 2>/dev/null | grep -c '"evt":"app.launch"')" -gt "$before" ]] && break
    sleep 0.5
  done
  sleep 1
  if [[ "${2:-}" == "kill" ]]; then pkill -9 -f "$APP/Contents/MacOS/TokenBe"; else osascript -e 'quit app "TokenBe"' >/dev/null; fi
  for i in $(seq 1 40); do pgrep -f "$APP/Contents/MacOS/TokenBe" >/dev/null || return 0; sleep 0.5; done
  echo "TokenBe did not exit"; return 1
}
count_evt() { cat "$1"/Logs/TokenBe/tokenbe-*.ndjson 2>/dev/null | grep -c "\"evt\":\"$2\""; }
no_errors() { ! cat "$1"/Logs/TokenBe/tokenbe-*.ndjson | grep -E '"lvl":"(error|fault)"'; }

root="$(mktemp -d)/tokenbe-verify"
check "clean launch and quit" launch_cycle "$root"
check "app.launch logged" test "$(count_evt "$root" app.launch)" -ge 1
check "app.terminate logged" test "$(count_evt "$root" app.terminate)" -eq 1
check "sentinel removed on clean quit" test ! -e "$root/Application Support/TokenBe/.running"
check "log directory is 0700" test "$(stat -f '%Lp' "$root/Logs/TokenBe")" = 700
check "second launch on top of the first run's data" launch_cycle "$root"
check "app.terminate logged twice" test "$(count_evt "$root" app.terminate)" -eq 2
check "zero error/fault records across both runs (D10)" no_errors "$root"

crash_root="$(mktemp -d)/tokenbe-verify-crash"
check "launch then kill -9" launch_cycle "$crash_root" kill
check "kill -9 leaves the sentinel" test -e "$crash_root/Application Support/TokenBe/.running"
check "relaunch after the kill" launch_cycle "$crash_root"
check "crash.previous_launch logged once" test "$(count_evt "$crash_root" crash.previous_launch)" -eq 1

check "StartupSequenceTests passed" suite_passed StartupSequenceTests
ui_check "UI tests (LaunchSmokeTests)" scripts/run.sh uitest
real_untouched() {
  local dir changed=""
  for dir in "$HOME/Library/Logs/TokenBe" "$HOME/Library/Application Support/TokenBe"; do
    [[ -d "$dir" ]] && changed+="$(find "$dir" -newer "$verify_started" -print)"
  done
  [[ -z "$changed" ]] || { echo "changed during verification: $changed"; return 1; }
}
check "owner's real TokenBe logs and support folder untouched by verification" real_untouched
check "owner's real TokenBe settings (tb.*) unchanged by verification" real_tb_unchanged
