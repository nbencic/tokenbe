import SwiftUI
import TokenBeCore

/// 08 § Account detail 4, the **By app** table (Paper `20N-0`; rows `210-0`, `21A-0`, `21J-0`): App | Key | badge |
/// Requests | Tokens (a stacked mini-bar by class) | Spend | Share. The `Total` row equals the account's spend for
/// the range (`Attribution`: Σ rows == provider total). An unbound key offers `Name…`, which creates an app and binds
/// the key (14 § Stage 7.1). Harness rows (7.2) carry `≈ split`, `harness` or `inferred` and are named by their app
/// tag. Core computes every figure (04 I3).
struct ByAppTable: View {
  let model: AppModel
  let summary: AccountSummary
  let hideCents: Bool
  @State private var naming: NamingTarget?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(Strings.byApp)
        .font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
        GridRow {
          ForEach([Strings.columnApp, Strings.columnKey, "", Strings.columnRequests, Strings.columnTokens,
                   Strings.columnSpend, Strings.columnShare], id: \.self) { title in
            Text(title).font(.caption).foregroundStyle(.secondary)
          }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
        ForEach(summary.byApp) { row in
          GridRow {
            appCell(row)
            Text(row.keyHint.map(Strings.hint) ?? Strings.noApp).monospaced().foregroundStyle(.secondary)
            AttributionBadge(kind: row.kind)
            Text(row.tokens.requests.formatted()).monospacedDigit().gridColumnAlignment(.trailing)
            TokenBar(tokens: row.tokens)
            Text(spend(row.spend)).monospacedDigit().gridColumnAlignment(.trailing)
            Text(Strings.percent(row.sharePercent)).monospacedDigit().gridColumnAlignment(.trailing)
          }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
        GridRow {
          Text(Strings.total).fontWeight(.semibold)
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          Text((summary.byAppTotal?.tokens.requests ?? 0).formatted()).monospacedDigit()
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          Text(summary.byAppTotal.map { spend($0.spend) } ?? Strings.noApp).fontWeight(.semibold).monospacedDigit()
            .accessibilityIdentifier("dashboard.account.byApp.total")
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        }
      }
    }
    .padding(16)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.account.byApp")
    .appNamePrompt($naming, model: model)
  }

  @ViewBuilder private func appCell(_ row: AppRow) -> some View {
    HStack(spacing: 6) {
      Text(Strings.appLabel(row))
        .accessibilityIdentifier("dashboard.account.byApp.name.\(row.elementID)")
      // An unbound key (never the keyless `Unassigned` row, never a harness app) can be named here (08).
      if row.kind == .key, row.appID == nil, !row.providerKeyID.isEmpty {
        Button(Strings.nameKey) {
          naming = NamingTarget(key: ProviderKeyRef(accountID: row.accountID, providerKeyID: row.providerKeyID),
                                suggestion: row.keyName ?? "")
        }
        .buttonStyle(.link)
        .accessibilityIdentifier("dashboard.account.byApp.name.\(row.providerKeyID).button")
      }
    }
  }

  private func spend(_ figure: SpendFigure) -> String {
    Formatters.spend(figure, currency: summary.currency, hideCents: hideCents, locale: .current)
  }
}

/// The attribution kind as a small capsule (08 badge `key`).
struct AttributionBadge: View {
  let kind: AttributionKind

  var body: some View {
    Text(Strings.badge(kind))
      .font(.caption2.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
  }
}

/// The Tokens cell (08): a stacked mini-bar by token class in the class colours, then the total.
struct TokenBar: View {
  let tokens: TokenClasses

  private var segments: [(Int64, Color)] {
    [(tokens.inputUncached, Color(.classInput)), (tokens.cacheWrite5m + tokens.cacheWrite1h, Color(.classCacheWrite)),
     (tokens.cacheRead, Color(.classCacheRead)), (tokens.output, Color(.classOutput)),
     (tokens.reasoning, Color(.classReasoning))]
  }

  var body: some View {
    HStack(spacing: 8) {
      GeometryReader { proxy in
        HStack(spacing: 0) {
          ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            segment.1.frame(width: width(segment.0, of: proxy.size.width))
          }
        }
      }
      .frame(width: 80, height: 6)
      .background(Color.secondary.opacity(0.15))
      .clipShape(Capsule())
      .accessibilityHidden(true)
      Text(tokens.tokens.formatted(.number.notation(.compactName))).monospacedDigit()
    }
  }

  private func width(_ count: Int64, of total: CGFloat) -> CGFloat {
    guard tokens.tokens > 0 else { return 0 }
    return total * CGFloat(count) / CGFloat(tokens.tokens)
  }
}

/// A key to name: `Name…` and `New app…` create an app from the typed display name and bind the key (O-16).
struct NamingTarget: Identifiable {
  let key: ProviderKeyRef
  let suggestion: String
  var id: String { "\(key.accountID)/\(key.providerKeyID)" }
}

extension View {
  /// The `App name` prompt: `Create` makes the app (its name is the O-16 slug) and binds the key in one write.
  func appNamePrompt(_ target: Binding<NamingTarget?>, model: AppModel) -> some View {
    modifier(AppNamePrompt(target: target, model: model))
  }
}

private struct AppNamePrompt: ViewModifier {
  @Binding var target: NamingTarget?
  let model: AppModel
  @State private var name = ""

  func body(content: Content) -> some View {
    content
      .alert(Strings.newApp, isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) {
        TextField(Strings.appNameField, text: $name)
          .accessibilityIdentifier("apps.newApp.name")
        Button(Strings.create) {
          if let key = target?.key { model.createApp(name, binding: key) }
          target = nil
        }
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("apps.newApp.create")
        Button(Strings.cancel, role: .cancel) { target = nil }
      }
      .onChange(of: target?.id) { name = target?.suggestion ?? "" }
  }
}
