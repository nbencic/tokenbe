# 08 — UI specification (V1)

Design source of truth: Paper file **"TokenBe — App"** (`https://app.paper.design/file/01M6ZTCNRVZYN35QB3XX0HQJ2D`). Pages: `01 Popover & Menu bar`, `02 Dashboard`, `03 Onboarding`, `04 Settings`. Where this doc and Paper disagree, **this doc wins** and Paper gets updated.

Implementation: SwiftUI only. No AppKit views except `NSStatusItem` fallback is NOT allowed — use `MenuBarExtra(.window)`. System fonts (SF Pro / SF Mono via `.system(design:)`); Paper's Inter is a stand-in only. All colors via `Color("…")` asset catalog names listed below; never literal hex in views.

## Design tokens → asset catalog names

| Token | Light | Dark | Asset name |
|---|---|---|---|
| ground | #FFFFFF | #1E1E20 | `Ground` |
| window | #F2F3F5 | #161618 | `Window` |
| label | #1C1C1E | #F2F2F7 | `Label` (use `.primary` in code) |
| secondary | #6B6F76 | #A1A1AA | `.secondary` |
| tertiary | #9A9FA6 | #71717A | `.tertiary` |
| accent | #0A66FF | #3B82F6 | `AccentColor` (respects system accent when `tb.ui.useSystemAccent` true) |
| health.healthy | #256B43 | #4ADE80 | `HealthHealthy` |
| health.watch | #8F6300 | #FBBF24 | `HealthWatch` |
| health.low | #B85412 | #FB923C | `HealthLow` |
| health.critical | #C12A2E | #F87171 | `HealthCritical` |
| health.unknown | #9A9FA6 | #71717A | `HealthUnknown` |
| class.input | #3478F6 | same | `ClassInput` |
| class.cacheWrite | #5856D6 | same | `ClassCacheWrite` |
| class.cacheRead | #2F9E8F | same | `ClassCacheRead` |
| class.output | #AF52DE | same | `ClassOutput` |
| class.reasoning | #E0559C | same | `ClassReasoning` |

All text/background pairs must meet WCAG AA 4.5:1 (health colors above were adjusted for this). Type scale: title 20/semibold, headline 15/semibold, body 13/regular, caption 11/regular, mono numerals `.monospacedDigit()` on every number.

## Formatting rules (shared `Formatters` enum; tests in 11)
- Money: whole units when `tb.ui.hideCents` (default true) → `$42`; else `$42.17`. Non-USD prefix `CN¥`. Estimates: `≈ $42 ± 3`. Negative remaining is clamped to `$0` and band `critical`.
- Runway: see 05 formatting; two paces as `~12 d · ~9 d today` (each pace formatted by 05's rule; aligned to 05 in Stage 1.1, 12 § R1).
- Tokens: `1.53M`, `212k`, `842`. Thousands separators per locale.
- Freshness: `just now` (<60 s), `2 min ago`, `1 h ago`, `yesterday`; stale → `stale · 3 h ago` in `HealthLow`.
- Dates: local calendar, `MMM d`.

## Menu bar glyph (Paper `7P-0`)
- Template image 18×18 pt, three states: **solid ring** (all accounts healthy/watch), **ring with notch** (any low/critical — color is NOT used in the menu bar; the notch conveys it), **dashed ring** (any stale or offline).
- Optional text metric right of the glyph, `tb.menubar.metric` ∈ `none | minRunway | minRemaining | todaySpend` (default `minRunway`), formatted compactly (`12d`, `$42`, `$3.10`). Width capped at 64 pt.
- Click → popover. ⌥-click → opens Dashboard (if `MenuBarExtra` cannot report modifier flags reliably, ⌥-click is dropped — `14 § Pass 2`). No right-click context menu in V1 (D-context-menu): all actions live in the popover footer.

## Popover (Paper `1-0`; width 360 pt, max height 560 pt, scrolls)
Order top→bottom:
1. **Header row**: title `TokenBe` (headline), right: `Refreshed 2 min ago` (caption, secondary) and a refresh button (`arrow.clockwise`, spins while any poll in flight).
2. **Alert banner** (only when any account is `low`/`critical`/`unknown` with anchor missing): single line, band color background at 12 % alpha, text ≤ 60 chars: `Anthropic: ~1 d left` / `OpenAI: set an anchor to see runway`. Tapping opens that account's detail.
3. **Account cards** (nodes `A-0`,`10-0`,`1N-0`,`2A-0`), sorted by `tb.popover.sort` ∈ `runway | remaining | name | manual` (default `runway` ascending; `unknown` sorts last). Each card:
   - Row 1: provider glyph + account label (`OpenAI`) + mode chip (`direct` none; `anchored` → `≈`; `spend_only` → `spend`) ; right: band dot 8 pt.
   - Row 2: **remaining** (`N-0` etc.) 20 pt semibold mono; `± M` 13 pt secondary beside it when anchored.
   - Row 3: **runway** (`K-0` etc.) caption: `~12 d · ~9 d today` ; `spend_only` shows `today $3.10 · 30 d $84`.
   - Row 4 (collapsed by default, chevron toggles, remembered per account `tb.popover.expanded.<provider>`): top 3 apps by today's spend as `weather-collector $1.20 · harness $0.40 · other $0.10`.
   - Stale overlay: card opacity 0.6, freshness in `HealthLow`.
   - Click → Dashboard account detail.
4. **Footer**: `Open dashboard` (⌘D), `Settings…` (⌘,), `Pause polling for 1 h` / `Resume`, `Quit` (⌘Q). Keyboard: ↑/↓ moves card focus, ⏎ opens.

### Popover states
- **No data yet** (per card, before the first successful poll): row 2 reads `No data yet`, row 3 freshness `never`. **Key missing**: row 2 reads `Key missing · Fix…` (opens Settings → Accounts).
- **Empty** (`45-0`): illustration-free; headline `No accounts yet`; body `Add a provider key to start tracking.`; primary button `Add account…` → onboarding.
- **Day-1 collecting** (`1XL-0`): shown per card while `burn_7d == nil`: runway row reads `Collecting… runway after 2 days of data`; remaining still shows.
- **Offline**: banner `Offline — showing last known values` (secondary tone, not a band color); all cards stale overlay.
- **Paused**: header replaces freshness with `Paused · resumes 14:30` and a `Resume` link.

## Dashboard window (`NavigationSplitView`, min 920×600, remembers frame `tb.ui.dashboardFrame`)
Sidebar: `Overview`, then one row per account (glyph, label, band dot), then `Apps` (all apps flattened). Toolbar: range picker `Today | 7 d | 30 d | 90 d` (default `7 d`, remembered), `Refresh`, `Export…` (CSV of current view).

### Overview (Paper `OA-0`)
1. **Headline** (`Q1-0`,`Q2-0`): the account with the SHORTEST `runway_min`: `Shortest runway: Anthropic · ~1 d` in band color; subline `Total remaining ≈ $312 ± 9 across 3 USD accounts + 1 non-USD`.
2. **Runway board** (rows `QD-0`,`QW-0`,`RE-0`,`RW-0`): table, one row per account: Account | Remaining (`≈` and ±) | Runway (two paces; column 176 pt) | Burn 7 d/day | Today | Freshness (124 pt) | Band dot. Sorted by runway ascending; `unknown` last with `Set anchor…` link in Runway cell.
3. **Spend by day** chart: Swift Charts stacked bars, one stack per day in range, segments per account (account colors from a fixed 8-step palette, assigned by sidebar order). Y in money, hover tooltip lists accounts. Empty state text `No spend in this range`.
4. **Apps this period**: top 8 apps by spend across accounts with badge per attribution kind (`key` / `≈ split` / `harness` / `inferred`). Row click → app filter in account detail.
5. **Cache savings tile**: `Saved $12 via cache (net of writes)`; shows `—` for providers where not computable (05).

### Account detail (Paper `8T-0`)
1. **Header** (`AM-0`,`AR-0`): provider glyph, label, mode chip, freshness, band pill. Right-aligned buttons: `Set anchor…` (anchored mode), `Add top-up…`, `Refresh`.
2. **Badges row** (`B1-0`): `Balance: direct|anchored|none` · `Usage: per key|org only|harness` · `Cost: provider|estimated` · `Lag: 5 min`. Each badge has a help popover with one sentence from 02.
3. **Numbers strip**: Remaining (with ±), Runway (two paces), Burn 7 d, Spend today, Spend in range, Unpriced in range (shown only if > 0, in `HealthWatch`).
4. **By app** table (`20N-0`; rows `210-0`,`21A-0`,`21J-0`): App | Key (hint `…a9f2` or `—`) | Attribution badge | Requests | Tokens (stacked mini-bar by class, class colors) | Spend | Share %. Footer row `Total` MUST equal provider total for the range (06 precedence). Unbound provider keys appear as `(unnamed key …a9f2)` with `Name…` link → creates an app.
5. **By model** table (`G7-0`): Model | Requests | Input | Cache write | Cache read | Output | Reasoning | Est. cost | Provider cost | Drift. Drift column `—` when no provider cost row; flagged cell in `HealthWatch` when `|drift| > threshold`.
6. **Sources strip** (`HP-0`): one chip per data source with last success and next due: `Usage · ok · 2 min ago · next 3 min`, `Cost · ok · 02:10`, `Balance · n/a`, `Harness · 3 files · 12 lines today`. Failed source → chip in `HealthLow` with the last error's human message (02 probe messages).
7. **Ledger** (anchored only): list of `ledger_event` rows newest first: date, kind, amount, note, source; swipe/⌫ to delete a user row (system rows cannot be deleted).

### Set anchor sheet
Fields: Amount (currency of account; decimal pad; required), As of (date-time, default now, cannot be future), Note (optional, 140 chars). Helper text: `Enter the balance shown on the provider's billing page right now.` Buttons `Cancel` / `Set anchor`. On save: insert `ledger_event(kind='anchor', source='user')`, recompute, log `ledger.anchor_set`.

### Add top-up sheet
Amount, Date (default now), Note. Insert `kind='topup'`.

## Onboarding (Paper `LZ-0`, `I4-0`, `JV-0`; sheet 520×440)
- **Step 1 — Pick provider**: 5 tiles (OpenAI, Anthropic, OpenRouter, DeepSeek, xAI) each with one caption from 02 (`Admin key required`, `Needs an Organization`, `Management key`, `Balance only · apps via harness`, `Balance only · apps via harness`). Footer `Cancel` (index 0) · `Continue`. Providers already added are disabled with `Added` caption.
- **Step 2 — Paste key**: secure field with `Paste` button; label (default provider name; editable); live validation of prefix per 02 (wrong prefix → inline `This looks like a project key. TokenBe needs an Admin key (sk-admin-…).`); `Test & continue` runs the probe sequence from 02 with a spinner and shows the probe's human message on failure (never raw JSON). Key is written to Keychain only after a successful probe.
- **Step 3 — First numbers**: shows what the probe discovered: mode (direct/anchored/spend_only), key count, currency; if anchored: inline `Set anchor…` with amount field and `Skip for now`; checkbox `Launch at login` (default on). `Done` closes and triggers an immediate poll.
Harness folder is NOT part of onboarding; it is discoverable in Settings → Sources and the empty By-app table (`Report apps from your harness →`).

## Settings (`Settings` scene; tabs; Paper `11D-0`,`14Z-0`,`XK-0`,`18L-0`,`1C7-0`,`1FT-0`)
Every control is bound to a key in 09. Tab layout per Paper; `Form` with `.formStyle(.grouped)`. Content and effects are specified in 09 — this doc only fixes placement:
- **General**: Launch at login; Menu bar glyph & metric; Pinned metric; Sort; Currency display (USD only in V1, disabled picker with caption `Conversion is not in v1`); Hide cents; Appearance; Global shortcut.
- **Accounts** (`1NL-0`, row `22Z-0` "Keys & apps"): list of accounts (184 pt) + detail: label, key status (`Valid · tested 2 min ago`), `Replace key…`, `Test`, `Remove account…` (destructive confirm; deletes Keychain item + DB rows), auto-reload toggle + threshold + amount (anchored accounts), **Keys & apps**: table of provider keys with name from provider, hint, bound app (picker of apps + `New app…`).
- **Sources** (`YP-0`; Harness reports `21S-0`; Price book `10V-0`): Refresh intervals per job; Low Power multiplier; `Run daily tasks now` (runs the daily activity out of band, `04`); **Harness reports** group: folder path (read-only, `Reveal in Finder`), watch toggle, move-when-done toggle, status line `Watching · 2 files · last line 14 s ago`, counters today (lines ok / dup / rejected), `Copy reporter snippet` menu (Python/Node); **Price book**: feed toggle, last refresh, `Refresh now`, overrides table (model, input/output/cache rates, `+`/`−`), `Reset to feed`.
- **Alerts** (`18L-0`): thresholds (days), dollar floor, stale multiplier, drift %, anchor age; notifications toggle per band; quiet hours; `Send test notification`; when notification authorization is denied, a banner `Notifications are off in System Settings` with an `Open System Settings` button (13 O-11).
- **Privacy** (`1C7-0`): static text: keys in Keychain; no telemetry; update check row (`1U1-0`/`1U2-0`: `Check for updates daily` + caption `One GET a day to the GitHub releases API. Sends nothing. Install via Homebrew or the release page — no in-app updater in v1.`) with toggle; `Open log folder`.
- **Advanced** (`1WN-0` Diagnostics; `22Q-0` Log files): log level picker; log retention; `Export diagnostics…`; `Open log folder`; retention days for hourly buckets and raw harness events; `Last daily run` (read-only); `Run integrity check now`; `Back up now`; `Export data (JSON)…` / `Import…` (import only into an empty database) / `Export CSV (all tables)…`; `Reset all settings…` (destructive confirm; does NOT touch keys or DB).

## Notifications (`UNUserNotificationCenter`)
- Sent on band transition INTO `low`, `critical`, `unknown`(anchor missing for > 24 h), and on `stale` for > 6 h. Not on transitions to better bands. Max one per account per band per 24 h. Suppressed during quiet hours (queued, sent at end). Body copy: `OpenAI: ~1 d of runway left (≈ $9 ± 2).` Action buttons: `Open`, `Snooze 24 h`.

## Accessibility
- Every band dot/pill has an `accessibilityLabel` with the band word; color is never the only carrier (glyph notch, text labels).
- Dynamic Type supported up to `xxLarge` in popover (cards reflow to 2 lines).
- All tables keyboard navigable; VoiceOver reads `Remaining, approximately 42 dollars, plus or minus 3`.
- Reduce Motion: no spinner rotation; use opacity pulse.

## Definition of done
- Every node id referenced above exists in Paper and matches this copy (manual check in Milestone 4).
- XCUITest state tests (11; D-no-pixel-snapshots) for popover states: no-data, empty, day-1, offline, paused, stale — asserted through accessibility identifiers and texts, in light and dark appearance.
- Overview footer `Total` equals Σ accounts in tests with mixed currencies (USD-only sum, `+ N non-USD` suffix).
