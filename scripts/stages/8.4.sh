# Stage 8.4 — Accessibility & input (14 § Stage 8.4, 08 § Accessibility). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
dash=$app/Dashboard
inventory=(
  $core/Model/SpokenFormatters.swift Tests/TokenBeCoreTests/SpokenFormattersTests.swift
  $app/Components/AccessibilityOverrides.swift $app/Components/TableKeyboard.swift
  Tests/TokenBeUITests/AccessibilityUITests.swift scripts/stages/8.4.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# VoiceOver reads every number in words with its title (Core `Spoken`; Q-054).
check "Core pins 08's sentence: Remaining, approximately 42 dollars, plus or minus 3" grep -qF '"Remaining, approximately 42 dollars, plus or minus 3"' Tests/TokenBeCoreTests/SpokenFormattersTests.swift
check "Spoken builds from Money and the band, not from display strings" bash -c "grep -qF 'public static func estimate(_ amount: Money, bandCents: Int64' $core/Model/SpokenFormatters.swift && ! grep -nE 'replacingOccurrences|components\\(separatedBy' $core/Model/SpokenFormatters.swift"
check "the popover card's rows carry their spoken text" bash -c "grep -qF '.accessibilityLabel(rows.spoken2 ?? Strings.noDataYet)' $app/Popover/AccountCardView.swift && grep -qF '.accessibilityLabel(rows.spoken3.joined' $app/Popover/AccountCardView.swift"
check "the numbers strip reads each cell as its title and words" bash -c "grep -qF '.accessibilityLabel(Strings.spoken(label, spoken))' $dash/NumbersStrip.swift && grep -qF '.accessibilityHidden(true)' $dash/NumbersStrip.swift"
check "the runway board, headline, totals and tables speak their figures" bash -c "grep -qF 'static func spokenCells' $dash/RunwayBoard.swift && grep -qF 'Strings.spokenTotalRemaining(' $dash/OverviewHeadline.swift && grep -qF 'Spoken.spend(row.spend' $dash/ByAppTable.swift && grep -qF 'Spoken.spend(SpendFigure(cents: cents, isEstimate: true)' $dash/ByModelTable.swift && grep -qF 'Spoken.money(' $dash/LedgerList.swift && grep -qF 'Spoken.spend(total.spend' $dash/AppsThisPeriod.swift"

# Colour is never the only carrier of a band (08).
check "band dot and pill name their band" bash -c "grep -qF '.accessibilityLabel(Strings.bandLabel(band.word))' $app/Components/BandDot.swift && grep -qF '.accessibilityLabel(Strings.bandLabel(band.word))' $dash/AccountDetailView.swift"
check "the band-coloured headline and the band-tinted banner say the band" bash -c "grep -qF 'band: shortest.band.word' $dash/OverviewHeadline.swift && grep -qF 'band: account.band.word' $app/Popover/AlertBanner.swift"

# Dynamic Type to xxLarge in the popover; the cards scale their own fonts (macOS text styles do not, Q-054).
check "the popover caps its text size at xxLarge" bash -c "grep -qF '.modifier(PopoverTextSize())' $app/Popover/PopoverView.swift && grep -qF 'dynamicTypeSize(...DynamicTypeSize.xxLarge)' $app/Components/AccessibilityOverrides.swift"
check "the cards' fonts follow the text size (no fixed font left in the card)" bash -c "grep -qF '.scaledFont(20, weight: .semibold, monospacedDigits: true)' $app/Popover/AccountCardView.swift && ! grep -nE '\\.font\\(' $app/Popover/AccountCardView.swift"

# Reduce Motion: no spinner rotation; an opacity pulse instead.
check "the refresh button pulses under Reduce Motion" bash -c "grep -qF 'if ReduceMotion(system: systemReduceMotion).isOn' $app/Popover/PopoverView.swift && grep -qF '.symbolEffect(.pulse, options: .repeat(.continuous), isActive: model.inFlightCount > 0)' $app/Popover/PopoverView.swift"
check "every spinner is a BusyIndicator (a pulse under Reduce Motion)" bash -c "! grep -rn 'ProgressView(' $app | grep -v 'Components/AccessibilityOverrides.swift'"
check "the test overrides exist only in DEBUG under a test root" bash -c "grep -qF 'environment[Startup.testRootVariable] != nil' $app/Components/AccessibilityOverrides.swift && [[ \$(grep -c '#if DEBUG' $app/Components/AccessibilityOverrides.swift) -ge 2 ]]"

# Tables are keyboard navigable (the ledger is a List).
for table in RunwayBoard ByAppTable ByModelTable; do
  check "$table rows take keyboard focus; ↑/↓ and Esc move it" bash -c "grep -qF '.tableRowFocus(' $dash/$table.swift && grep -qF '.tableKeyboard(' $dash/$table.swift"
done
check "the ledger stays a selectable List" grep -qF 'List(selection: $selection)' $dash/LedgerList.swift

# Carry-forwards: PM-8.2-2 (per-day totals without a pointer), PM-8.2-1 (board name column), PM-7.3-3 (⌥-click).
check "the chart exposes every day's total (PM-8.2-2)" bash -c "grep -qF 'dashboard.spendByDay.day.' $dash/SpendByDayChart.swift && grep -qF 'dashboard.spendByDay.day.' Tests/TokenBeUITests/DrilldownUITests.swift"
check "the board's account name keeps one line (PM-8.2-1)" bash -c "grep -A2 'Text(cells\\[0\\])' $dash/RunwayBoard.swift | grep -qF '.fixedSize()'"
check "the ⌥-click waits for a finite frame and logs it (PM-7.3-3)" grep -qF 'PM-7.3-3 status item frame before' Tests/TokenBeUITests/DashboardShellUITests.swift

check "suite SpokenFormattersTests passed" suite_passed SpokenFormattersTests
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "AccessibilityUITests passed (08's sentence, xxLarge, keyboard focus, audit)" grep -q "Test Suite 'AccessibilityUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
