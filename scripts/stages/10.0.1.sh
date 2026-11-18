# Stage 10.0.1 — Add and remove accounts from the sidebar; soak-safe verify (14 § Stage 10.0.1, Q-060, Q-061).
# Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
sidebar=$app/Dashboard/SidebarView.swift
accounts=$app/SettingsUI/AccountsTab.swift
inventory=(
  $sidebar $app/Dashboard/DashboardView.swift $accounts $app/Strings.swift scripts/verify-stage.sh
  scripts/stages/0.4.sh scripts/stages/2.1.sh scripts/stages/4.1.sh scripts/stages/9.5.sh scripts/stages/10.0.1.sh
  docs/08-ui-spec.md Tests/TokenBeUITests/SidebarAccountsUITests.swift
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 3: the sidebar's foot.
check "the sidebar's foot is a bottom inset under a divider" bash -c "grep -qF '.safeAreaInset(edge: .bottom, spacing: 0) { foot }' $sidebar && grep -A2 'private var foot: some View' $sidebar | grep -qF 'Divider()'"
check "+ opens Add account (model.showOnboarding)" bash -c "grep -qF 'Button { model.showOnboarding() } label: {' $sidebar && grep -qF 'Image(systemName: \"plus\")' $sidebar"
check "− opens the remove confirm" bash -c "grep -qF 'Button { confirmingRemove = true } label: {' $sidebar && grep -qF 'Image(systemName: \"minus\")' $sidebar"
check "ids dashboard.sidebar.add / .remove" bash -c "grep -qF '.accessibilityIdentifier(\"dashboard.sidebar.add\")' $sidebar && grep -qF '.accessibilityIdentifier(\"dashboard.sidebar.remove\")' $sidebar"
check "help and accessibility labels Add account / Remove account" bash -c "for k in sidebarAddAccount sidebarRemoveAccount; do grep -qF \".help(Strings.\$k)\" $sidebar && grep -qF \".accessibilityLabel(Strings.\$k)\" $sidebar || exit 1; done"
check "Strings: Add account and Remove account, no ellipsis (08)" bash -c "grep -qF 'static let sidebarAddAccount = \"Add account\"' $app/Strings.swift && grep -qF 'static let sidebarRemoveAccount = \"Remove account\"' $app/Strings.swift"
check "+ is off once every offered provider has an account" bash -c "grep -qF '.disabled(!canAdd)' $sidebar && grep -qF 'environment?.registry.availableForOnboarding.contains { !added.contains(\$0) } ?? false' $sidebar"
check "− is gated on an account selection (not Overview, not Apps)" bash -c "grep -qF '.disabled(selectedRecord == nil)' $sidebar && grep -A2 'private var selectedRecord: AccountRecord?' $sidebar | grep -qF 'guard case .account(let id) = selection else { return nil }'"
check "both are standard (borderless) buttons, so the keyboard reaches them (8.4)" bash -c "grep -qF '.buttonStyle(.borderless)' $sidebar && ! grep -qF 'onTapGesture' $sidebar"
check "after a removal the sidebar selects Overview" grep -qF 'view: "dashboard.sidebar") { selection = .overview }' $sidebar
check "DashboardView passes the model to the sidebar" grep -qF 'SidebarView(model: model, selection: $model.dashboardSelection)' $app/Dashboard/DashboardView.swift

# The confirm and its action exist once, shared by Settings → Accounts and the sidebar.
check "shared confirm: RemoveAccountConfirm in AccountsTab.swift" grep -qF 'struct RemoveAccountConfirm: ViewModifier {' $accounts
check "shared confirm: both views use it" bash -c "grep -qF '.removeAccountConfirm(record, isPresented: \$confirmingRemove' $accounts && grep -qF '.removeAccountConfirm(selectedRecord, isPresented: \$confirmingRemove' $sidebar"
check "shared confirm: one Remove account… dialog in the app" test "$(grep -rF 'confirmationDialog(Strings.removeAccountQuestion' $app | wc -l)" -eq 1
check "shared confirm: polls stop before the removal (Q-034)" bash -c "grep -A5 'private func remove()' $accounts | grep -qF 'await coordinator?.stop(record.id)' && grep -A8 'private func remove()' $accounts | grep -qF 'try await lifecycle.remove(record, settings: environment.settings)'"

# Step 4: 08 and 14 § 13.4.
check "08's sidebar line has the + / − foot (Q-060)" bash -c "grep -F 'Sidebar: \`Overview\`' docs/08-ui-spec.md | grep -qF '\`+\` (help and accessibility label \`Add account\`)' && grep -F 'Sidebar: \`Overview\`' docs/08-ui-spec.md | grep -qF '\`−\` (help and accessibility label \`Remove account\`)'"
check "14 § 13.4 maps the foot to 10.0.1" grep -qF 'Apps section 7.1, `+` / `−` foot 10.0.1' docs/14-development-plan.md

# Step 2: the soak switch.
check "verify-stage.sh: TB_SOAK=1 forces UI tests off and prints one banner" bash -c "grep -qF 'SOAK=1; TB_UI_TESTS=0' scripts/verify-stage.sh && test \$(grep -c 'echo \"soak: TB_SOAK=1' scripts/verify-stage.sh) -eq 1"
check "verify-stage.sh: STAGES runs 10.0.1 after 9.5" bash -c "grep -A1 ' 9.4 9.5\$' scripts/verify-stage.sh | grep -qE '^ +10\\.0\\.1 10\\.1 '"
launch_checks_routed() { # every check of a launch, or of what a launch left, goes through launch_check(_for)
  local f want got
  for f in 0.4:12 2.1:7 4.1:2 9.5:5; do
    want="${f#*:}"; got="$(grep -cE '^launch_check(_for)? ' "scripts/stages/${f%%:*}.sh")"
    [[ "$got" == "$want" ]] || { echo "${f%%:*}.sh: $got launch checks, want $want"; return 1; }
  done
  ! grep -nE '^(check|ui_check|ui_check_for) .*(launch_cycle|launch_and_inspect|launch_once|cadence_run|cadence_ok|count_evt|no_errors|no_db_errors|clean_audit|logged_|steps_in_order|launch_fields|\.running|Logs/TokenBe)' \
    scripts/stages/{0.4,2.1,4.1,9.5}.sh
}
check "0.4, 2.1, 4.1, 9.5: every launch check runs through launch_check" launch_checks_routed
soak_dry_run() { # launch_check, launch_check_for and the real-domain guards under both values of SOAK
  local out
  out="$( SOAK=1; launch_check "dry run" false )"
  [[ "$out" == "skip ${STAGE} dry run (soak running: TB_SOAK=1)" ]] || { echo "SOAK=1 launch_check: $out"; return 1; }
  out="$( SOAK=1; launch_check_for RefreshPauseUITests "dry run" false )"
  [[ "$out" == "skip ${STAGE} dry run (soak running: TB_SOAK=1)" ]] || { echo "SOAK=1 launch_check_for: $out"; return 1; }
  out="$( SOAK=1; check "dry run" real_tb_unchanged )"
  [[ "$out" == "skip ${STAGE} dry run"* ]] || { echo "SOAK=1 real-domain guard: $out"; return 1; }
  out="$( SOAK=0; launch_check "dry run" true )"
  [[ "$out" == "ok   ${STAGE} dry run" ]] || { echo "SOAK=0 launch_check: $out"; return 1; }
  out="$( SOAK=0; launch_check "dry run" false )" && { echo "SOAK=0 launch_check passed a failing check"; return 1; }
  [[ "$out" == "FAIL ${STAGE} dry run"* ]] || { echo "SOAK=0 failing launch_check: $out"; return 1; }
}
check "TB_SOAK=1 turns each launch check into skip (dry run under both values)" soak_dry_run

check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "SidebarAccountsUITests passed (+ adds xAI, − removes it, Overview selected)" grep -q "Test Suite 'SidebarAccountsUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
