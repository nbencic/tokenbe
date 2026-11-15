import SwiftUI
import TokenBeCore

/// 08 § Account detail 7 (anchored accounts): the account's `ledger_event` rows, newest first — date, kind, amount,
/// note, source. A user row can be deleted (its trash button, or ⌫ on the selected row); a system row cannot (R7,
/// enforced again in SQL).
struct LedgerList: View {
  let events: [LedgerEventRecord]
  let currency: Currency
  let hideCents: Bool
  let delete: (LedgerEventRecord) -> Void
  @State private var selection: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(Strings.ledger)
        .font(.headline)
      if events.isEmpty {
        Text(Strings.ledgerEmpty)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("dashboard.ledger.empty")
      } else {
        List(selection: $selection) {
          ForEach(events.reversed(), id: \.id) { event in
            row(event).tag(event.id)
          }
        }
        .frame(minHeight: CGFloat(min(events.count, 6)) * 28 + 12)
        .onDeleteCommand {
          if let selection, let event = events.first(where: { $0.id == selection }), event.source == "user" {
            delete(event)
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.ledger")
  }

  private func row(_ event: LedgerEventRecord) -> some View {
    HStack(spacing: 12) {
      Text(DBTime.date(event.ts).map { Formatters.date($0, calendar: .current) } ?? event.ts)
        .frame(width: 64, alignment: .leading)
      Text(Strings.ledgerKind(event.kind))
        .frame(width: 80, alignment: .leading)
      Text(event.amountCents.map {
        Formatters.money(Money(cents: $0, currency: currency), hideCents: hideCents, locale: .current)
      } ?? "\u{2014}")
        .monospacedDigit()
        .frame(width: 90, alignment: .trailing)
      Text(event.note ?? "")
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer()
      Text(event.source)
        .font(.caption)
        .foregroundStyle(.secondary)
      if event.source == "user" {
        Button {
          delete(event)
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help(Strings.delete)
        .accessibilityLabel(Strings.delete)
        .accessibilityIdentifier("dashboard.ledger.delete.\(event.kind)")
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("dashboard.ledger.row.\(event.kind)")
  }
}
