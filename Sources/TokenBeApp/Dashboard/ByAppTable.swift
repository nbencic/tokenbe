import SwiftUI
import TokenBeCore

/// 08 § Account detail 4, the **By app** table (Paper `20N-0`; rows `210-0`, `21A-0`, `21J-0`): App | Key | badge |
/// Requests | Tokens (a stacked mini-bar by class) | Spend | Share. The `Total` row equals the account's spend for
/// the range (`Attribution`: Σ rows == provider total). An unbound key offers `Name…`, which creates an app and binds
/// the key (14 § Stage 7.1). Harness rows (7.2) carry `≈ split`, `harness` or `inferred` and are named by their app
/// tag. Core computes every figure (04 I3). With an app filter (7.3: an Overview `Apps this period` row) the table
/// shows that app's rows under a chip `App: <name> ✕`, and its total row reads `App total` (Q-050).
struct ByAppTable: View {
  let model: AppModel
  let summary: AccountSummary
  let hideCents: Bool
  var filter: AppFilter?
  var clearFilter: () -> Void = {}
  @State private var naming: NamingTarget?

  private var shown: (rows: [AppRow], total: AppRowsTotal?) {
    filter.map { Attribution.filtered(summary.byApp, appKey: $0.appKey) } ?? (summary.byApp, summary.byAppTotal)
  }

  var body: some View {
    let shown = shown
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text(Strings.byApp)
          .font(.headline)
        if let filter {
          FilterChip(label: Strings.appFilter(filter.label), clear: clearFilter)
        }
      }
      if let filter, shown.rows.isEmpty {
        Text(Strings.noAppSpend(filter.label))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("dashboard.account.byApp.filter.empty")
      }
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
        GridRow {
          ForEach(Array(Self.columns.enumerated()), id: \.offset) { index, title in
            // The badge column has no title on screen (08); the CSV names it.
            Text(index == 2 ? "" : title).font(.caption).foregroundStyle(.secondary)
          }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
        ForEach(shown.rows) { row in
          let cells = Self.cells(row, currency: summary.currency, hideCents: hideCents)
          GridRow {
            appCell(row, label: cells[0])
            Text(cells[1]).monospaced().foregroundStyle(.secondary)
            AttributionBadge(kind: row.kind)
            Text(cells[3]).monospacedDigit().gridColumnAlignment(.trailing)
            TokenBar(tokens: row.tokens)
            Text(cells[5]).monospacedDigit().gridColumnAlignment(.trailing)
            Text(cells[6]).monospacedDigit().gridColumnAlignment(.trailing)
          }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
        let total = Self.totalCells(shown.total, filtered: filter != nil, currency: summary.currency,
                                    hideCents: hideCents)
        GridRow {
          Text(total[0]).fontWeight(.semibold)
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          Text(total[3]).monospacedDigit()
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          Text(total[5]).fontWeight(.semibold).monospacedDigit()
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

  @ViewBuilder private func appCell(_ row: AppRow, label: String) -> some View {
    HStack(spacing: 6) {
      Text(label)
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

  /// 08's columns; the third (the attribution badge) is untitled on screen and `Attribution` in the CSV (Q-053).
  static let columns = [Strings.columnApp, Strings.columnKey, Strings.columnAttribution, Strings.columnRequests,
                        Strings.columnTokens, Strings.columnSpend, Strings.columnShare]

  /// One row's cells, as the table prints them; the CSV export (8.3) writes the same strings. The Tokens cell is the
  /// mini-bar's total.
  static func cells(_ row: AppRow, currency: Currency, hideCents: Bool) -> [String] {
    [Strings.appLabel(row), row.keyHint.map(Strings.hint) ?? Strings.noApp, Strings.badge(row.kind),
     row.tokens.requests.formatted(), TokenBar.label(row.tokens),
     Formatters.spend(row.spend, currency: currency, hideCents: hideCents, locale: .current),
     Strings.percent(row.sharePercent)]
  }

  /// The footer: `Total` (or `App total` under a filter), requests and spend; the other cells are empty.
  static func totalCells(_ total: AppRowsTotal?, filtered: Bool, currency: Currency, hideCents: Bool) -> [String] {
    [filtered ? Strings.appTotal : Strings.total, "", "", (total?.tokens.requests ?? 0).formatted(), "",
     total.map { Formatters.spend($0.spend, currency: currency, hideCents: hideCents, locale: .current) }
       ?? Strings.noApp, ""]
  }

  /// The table as the account page's `Export…` writes it (8.3): the rows shown (the app filter applies), then the
  /// footer.
  static func csvTable(_ summary: AccountSummary, filter: AppFilter?, hideCents: Bool) -> CSVTable {
    let shown: (rows: [AppRow], total: AppRowsTotal?) = filter.map {
      Attribution.filtered(summary.byApp, appKey: $0.appKey)
    } ?? (summary.byApp, summary.byAppTotal)
    return CSVTable(header: columns, rows: shown.rows.map { cells($0, currency: summary.currency, hideCents: hideCents) }
      + [totalCells(shown.total, filtered: filter != nil, currency: summary.currency, hideCents: hideCents)])
  }
}

/// The account page's app filter (7.3): set by an Overview `Apps this period` row for one account, cleared by the
/// chip's ✕ or by selecting another page (`DashboardView`). Not persisted.
struct AppFilter: Equatable {
  let accountID: String
  /// `AppRow.appKey`.
  let appKey: String
  let label: String
}

/// `App: news-digest ✕`.
struct FilterChip: View {
  let label: String
  let clear: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .accessibilityIdentifier("dashboard.account.byApp.filter")
      Button(Strings.clearAppFilter, systemImage: "xmark.circle.fill") { clear() }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help(Strings.clearAppFilter)
        .accessibilityIdentifier("dashboard.account.byApp.filter.clear")
    }
    .font(.callout)
    .padding(.leading, 8)
    .padding(.trailing, 4)
    .padding(.vertical, 2)
    .background(Color.accentColor.opacity(0.12), in: Capsule())
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
      Text(Self.label(tokens)).monospacedDigit()
    }
  }

  /// The bar's total, compact (`1.2M`).
  static func label(_ tokens: TokenClasses) -> String {
    tokens.tokens.formatted(.number.notation(.compactName))
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
