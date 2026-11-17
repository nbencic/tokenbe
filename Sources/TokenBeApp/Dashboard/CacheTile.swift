import SwiftUI
import TokenBeCore

/// 08 § Overview 5, the **cache savings tile** (14 § Stage 8.2): `Saved $12 via cache (net of writes)` over the
/// Dashboard range, summed over the accounts whose savings are computed (05 § Cache savings), then one line per
/// account: its saving, or `—` with the reason in its help (OpenAI: aggregate cache counts are unreliable). Savings
/// are price-book dollars whatever the account's currency (Q-052). Core computes every figure (04 I3).
struct CacheTile: View {
  let accounts: [AccountSummary]
  let hideCents: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(Strings.cacheSavings)
        .font(.headline)
      Group {
        if let total = CacheSavings.total(accounts) {
          Text(Strings.cacheSaved(amount(total)))
            .help(Strings.cacheSavedHelp)
        } else {
          Text(Strings.cacheNotComputed)
            .foregroundStyle(.secondary)
        }
      }
      .font(.title3.weight(.semibold))
      .accessibilityIdentifier("dashboard.cacheSavings.headline")
      ForEach(accounts) { account in
        HStack(spacing: 8) {
          Text(account.label)
          Spacer()
          Group {
            if let cents = account.cacheSavings?.cents {
              Text(amount(cents))
                .monospacedDigit()
                .help(Strings.cacheSavedHelp)
            } else {
              Text(Strings.cacheGap)
                .foregroundStyle(.secondary)
                .help(Strings.cacheGapHelp(gap(account.cacheSavings)))
                .accessibilityLabel(Strings.cacheGapHelp(gap(account.cacheSavings)))
            }
          }
          .accessibilityIdentifier("dashboard.cacheSavings.value.\(account.provider.rawValue)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.cacheSavings.row.\(account.provider.rawValue)")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.cacheSavings")
  }

  /// `$12`, or `−$3` when writes cost more than reads saved.
  private func amount(_ cents: Int64) -> String {
    let money = Money(cents: cents, currency: .usd)
    return cents < 0 ? Formatters.signedMoney(money, hideCents: hideCents, locale: .current)
      : Formatters.money(money, hideCents: hideCents, locale: .current)
  }

  private func gap(_ figure: CacheSavingsFigure?) -> CacheSavingsGap? {
    if case .notComputed(let gap) = figure { return gap }
    return nil
  }
}
