# Stage 0.3 — Settings core (14 § Stage 0.3, 09 § Definition of done). Sourced by scripts/verify-stage.sh.

inventory=(
  Sources/TokenBeCore/Settings/SettingsStore.swift Sources/TokenBeCore/Settings/UserDefaultsStore.swift
  Sources/TokenBeCore/Settings/SettingsKey.swift Sources/TokenBeCore/Settings/SettingSpec.swift
  Sources/TokenBeCore/Settings/Settings.swift Sources/TokenBeCore/Settings/Settings+Accessors.swift
  Tests/TokenBeCoreTests/SettingsTests.swift scripts/stages/0.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 09 is the registration list: its keys and SettingsKey must match exactly, both directions.
settings_keys_match() {
  local doc enum
  doc="$(grep -oE '^\| `tb\.[A-Za-z0-9_.]+`' docs/09-settings-spec.md | tr -d '|` ' | sort)"
  enum="$(grep -oE '= "tb\.[A-Za-z0-9_.]+"' Sources/TokenBeCore/Settings/SettingsKey.swift | cut -d'"' -f2 | sort)"
  diff <(echo "$doc") <(echo "$enum")
}
check "09 keys ↔ SettingsKey" settings_keys_match
check "09 templated keys present" grep -q 'tb.popover.expanded"' Sources/TokenBeCore/Settings/SettingSpec.swift
check "09 templated keys present (snooze)" grep -q 'tb.alerts.snoozedUntil"' Sources/TokenBeCore/Settings/SettingSpec.swift

check "swift test" scripts/run.sh test
for suite in SettingsTests; do
  check "suite $suite passed" suite_passed "$suite"
done

no_userdefaults() { [[ "$(grep -R "UserDefaults" Sources/ | grep -v Settings/UserDefaultsStore.swift | wc -l | tr -d ' ')" == "0" ]]; }
check "UserDefaults only in Settings/UserDefaultsStore.swift (09 DoD)" no_userdefaults
for evt in app.settings_changed app.settings_reset; do
  check "Settings emits $evt" grep -q "\.$(python3 -c "import sys;p=sys.argv[1].split('.')[1].split('_');print('app'+''.join(x.capitalize() for x in p))" "$evt")" Sources/TokenBeCore/Settings/Settings.swift
done
