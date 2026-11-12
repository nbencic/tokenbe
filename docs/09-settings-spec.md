# 09 — Settings specification (every key, type, default, range, effect)

Storage: `UserDefaults(suiteName: "dev.bathyon.tokenbe")` behind the `SettingsStore` seam (`14 § 0.3`), all keys prefixed `tb.`. Access ONLY through `enum SettingsKey: String, CaseIterable` + an `@Observable @MainActor final class Settings` wrapper that validates ranges on write (out-of-range → clamp + log `app.settings_changed` with `clamped=true`). Direct `UserDefaults` calls outside `Settings/UserDefaultsStore.swift` are a lint failure.

Every change emits `app.settings_changed {key, old, new}` and posts `Settings.didChange` (a `Notification.Name`) with the key; the scheduler and UI subscribe. Defaults are registered via `UserDefaults.register(defaults:)` at launch from the table below — the table IS the registration list; generate it, do not hand-type twice.

Legend: **Effect** says exactly what consumes the value. "Restart" means the change applies at next launch; otherwise immediate.

## General
| Key | Type | Default | Range / values | Effect |
|---|---|---|---|---|
| `tb.general.launchAtLogin` | Bool | `true` | — | `SMAppService.mainApp.register()/unregister()` on change; mirrors actual status at launch (if the system says unregistered, the toggle shows off and logs `app.settings_changed source=system`). |
| `tb.menubar.glyphStyle` | String | `ring` | `ring` | Only one style in V1; key exists for forward-compat. |
| `tb.menubar.metric` | String | `minRunway` | `none`,`minRunway`,`minRemaining`,`todaySpend` | Text shown beside glyph (08). |
| `tb.popover.pinnedMetric` | String | `runway` | `runway`,`remaining`,`todaySpend` | Which metric is row 2 (large) on popover cards; the other two move to row 3. |
| `tb.popover.sort` | String | `runway` | `runway`,`remaining`,`name`,`manual` | Card order; `manual` uses `tb.popover.manualOrder`. |
| `tb.popover.manualOrder` | [String] | `[]` | provider ids | Only read when sort = `manual`; missing providers appended in name order. |
| `tb.popover.expanded.<provider>` | Bool | `false` | — | Per-account apps row expansion (08 §3 row 4). |
| `tb.ui.currencyDisplay` | String | `native` | `native` | Picker disabled in V1 (08). |
| `tb.ui.hideCents` | Bool | `true` | — | `Formatters.money` whole units vs 2 decimals. |
| `tb.ui.appearance` | String | `system` | `system`,`light`,`dark` | `preferredColorScheme` on all scenes. |
| `tb.ui.useSystemAccent` | Bool | `true` | — | When true, `AccentColor` resolves to `Color.accentColor`; else token #0A66FF. |
| `tb.ui.shortcut` | String | `ctrl+alt+t` | `modifier(+modifier)*+key`; empty = none | Global hotkey toggles the Dashboard window (opens and activates it; closes it when it is the front window). `MenuBarExtra` cannot be opened from code on macOS 26+, so it cannot toggle the popover (Q-023). Implement with Carbon `RegisterEventHotKey` (works without Accessibility permission). `NSEvent.addGlobalMonitorForEvents` is NOT allowed (needs Accessibility, cannot consume the event). |
| `tb.ui.dashboardFrame` | String | `""` | `NSStringFromRect` | Window frame restore. |
| `tb.ui.dashboardRange` | String | `7d` | `today`,`7d`,`30d`,`90d` | Dashboard range picker. |
| `tb.ui.onboardingDone` | Bool | `false` | — | Show onboarding at launch when false AND no accounts. |

## Accounts (per account; stored in DB `account` table, NOT UserDefaults — listed here because the UI lives in Settings → Accounts)
| Column | Type | Default | Range | Effect |
|---|---|---|---|---|
| `account.label` | TEXT | provider display name | 1–40 chars | Sidebar/card title. |
| `account.paused` | INTEGER | 0 | 0/1 | Scheduler skips all jobs for the account (`sched.skip reason=paused`). |
| `account.auto_reload_enabled` | INTEGER | 0 | 0/1 | Enables runway override "reloads at $X" (05). |
| `account.auto_reload_below_cents` | INTEGER | NULL | ≥ 0 | Threshold. |
| `account.auto_reload_to_cents` | INTEGER | NULL | ≥ 0 | Amount the provider adds per reload; shown in the note `reloads +$50 at $10`. Not used in math. |
| `account.interval_override_json` | TEXT | NULL | JSON `{usage?, cost?, balance?, keys?}` seconds; each value within the range of the global key it overrides (clamped + `app.settings_changed clamped=true source=system`, Q-034) | Overrides the global intervals below for that account (Accounts tab → `Refresh intervals`). `cost` runs in the daily activity (04), so its override is not read. |

## Sources
| Key | Type | Default | Range | Effect |
|---|---|---|---|---|
| `tb.poll.balanceIntervalS` | Int | `60` | 30–3600 | Balance job period (openrouter, deepseek, xai). |
| `tb.poll.usageIntervalAnthropicS` | Int | `60` | 60–3600 | Anthropic usage job period (02 permits 1/min). |
| `tb.poll.usageIntervalOpenAIS` | Int | `300` | 60–3600 | OpenAI usage job period. |
| `tb.poll.keysIntervalS` | Int | `3600` | 600–86400 | Key-listing job period. |
| `tb.daily.lastRunAt` | Double | `0` | epoch | Written after each daily activity run (`04`); shown in Advanced as `Last daily run`. |
| `tb.daily.runCount` | Int | `0` | ≥ 0 | Counter; every 7th run performs the full `integrity_check`. |
| `tb.poll.lowPowerMultiplier` | Int | `4` | 1–10 | Intervals × this when `ProcessInfo.isLowPowerModeEnabled`. |
| `tb.poll.pausedUntil` | Double | `0` | epoch seconds | Global pause (menu bar "Pause 1 h"); 0 = not paused. |
| `tb.ingest.enabled` | Bool | `true` | — | Start/stop FSEvents stream (06). |
| `tb.ingest.moveWhenDone` | Bool | `true` | — | 06 §5. |
| `tb.ingest.folderPath` | String | fixed | read-only | `~/Library/Application Support/TokenBe/ingest`; displayed, not editable in V1. |
| `tb.price.feedEnabled` | Bool | `true` | — | Daily LiteLLM fetch (02). When false, only overrides + last cached snapshot are used. |
| `tb.price.feedURL` | String | LiteLLM raw URL (02) | https URL | Editable in Advanced only. |
| `tb.price.staleAfterDays` | Int | `7` | 1–60 | Price snapshot older than this → `price.stale` warning in Sources strip. |

## Alerts
| Key | Type | Default | Range | Effect |
|---|---|---|---|---|
| `tb.alerts.watchDays` | Int | `14` | > lowDays, ≤ 365 | Band `watch` threshold (05). |
| `tb.alerts.lowDays` | Int | `7` | > criticalDays | Band `low`. |
| `tb.alerts.criticalDays` | Int | `2` | ≥ 0 | Band `critical`. Validation: critical < low < watch, else clamp with log. |
| `tb.alerts.dollarFloorCents` | Int | `500` | 0–100000 | Band `critical` when remaining below. |
| `tb.alerts.staleMultiplier` | Int | `3` | 2–10 | Stale overlay (05). |
| `tb.alerts.driftThresholdPct` | Int | `10` | 1–100 | Drift flag (05). |
| `tb.alerts.anchorAgeDays` | Int | `30` | 7–365 | `age_factor` step (05) and "anchor is N days old" nudge in account header when exceeded. |
| `tb.alerts.notify.low` | Bool | `true` | — | Notification on → low. |
| `tb.alerts.notify.critical` | Bool | `true` | — | → critical. |
| `tb.alerts.notify.unknown` | Bool | `true` | — | anchor missing > 24 h. |
| `tb.alerts.notify.stale` | Bool | `true` | — | stale > 6 h. |
| `tb.alerts.quietHoursEnabled` | Bool | `true` | — | — |
| `tb.alerts.quietStart` | String | `23:00` | `HH:mm` | Local time. |
| `tb.alerts.quietEnd` | String | `07:00` | `HH:mm` | May wrap midnight. |
| `tb.alerts.snoozedUntil.<provider>` | Double | `0` | epoch | From notification `Snooze 24 h`. |

## Privacy
| Key | Type | Default | Range | Effect |
|---|---|---|---|---|
| `tb.update.checkEnabled` | Bool | `true` | — | Daily GitHub releases GET (02/04). |
| `tb.update.lastCheckedAt` | Double | `0` | epoch | — |
| `tb.update.latestSeen` | String | `""` | semver | Badge "Update available" in Privacy tab and popover footer when newer than bundle version. |
| `tb.update.ignoredVersion` | String | `""` | semver | "Skip this version". |

## Advanced
| Key | Type | Default | Range | Effect |
|---|---|---|---|---|
| `tb.log.level` | String | `info` | `debug`,`info`,`warn`,`error` | Minimum level written to the NDJSON sink and os.Logger. |
| `tb.log.retentionDays` | Int | `14` | 1–90 | 07 rotation. |
| `tb.retention.hourlyDays` | Int | `90` | 30–730 | Hourly → daily roll-up horizon (03). |
| `tb.retention.rawHarnessDays` | Int | `90` | 7–730 | `harness_event` rows older than this are deleted after roll-up into `usage_bucket`. |
| `tb.db.lastBackupAt` | Double | `0` | epoch | — |
| `tb.db.lastIntegrityCheckAt` | Double | `0` | epoch | Weekly check gate. |
| `tb.debug.fixtureMode` | Bool | `false` | — | DEBUG builds only: providers read from `Fixtures/` instead of the network (11). Ignored in Release. |

## Reset semantics
- `Reset all settings…` removes every `tb.*` key EXCEPT `tb.ui.onboardingDone`, then re-registers defaults. Keychain, DB, logs untouched. Logs `app.settings_reset`.
- Removing an account deletes its `account` row (cascade), its Keychain item, its `tb.popover.expanded.<provider>` and `tb.alerts.snoozedUntil.<provider>` keys.

## Definition of done
- A test iterates `SettingsKey.allCases`, asserts each has a registered default and that writing a below-range and above-range value clamps and logs.
- A test asserts `critical < low < watch` repair.
- `grep -R "UserDefaults" Sources/ | grep -v Settings/UserDefaultsStore.swift` returns nothing.
