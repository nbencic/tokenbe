import Foundation
import Observation
import TokenBeCore

/// The app's side of Core's `PriceBook` (14 § Stage 5.1): mirrors its status for Settings → Sources → Price book
/// and the account page's `Prices` chip, and runs the refresh that both `Refresh now` and the daily activity's
/// `price refresh` step use (09 `tb.price.*` read at call time).
@MainActor @Observable
final class PriceBookModel {
  private(set) var status = PriceBook.Status()
  private(set) var isRefreshing = false
  @ObservationIgnored let book: PriceBook
  @ObservationIgnored private let fetcher: PriceFeedFetcher
  @ObservationIgnored private let settings: TokenBeCore.Settings
  @ObservationIgnored private var watcher: Task<Void, Never>?

  init(book: PriceBook, transport: any HTTPTransport, settings: TokenBeCore.Settings) {
    self.book = book
    fetcher = PriceFeedFetcher(transport: transport)
    self.settings = settings
    watcher = Task { [weak self] in
      for await status in await book.updates() {
        self?.status = status
      }
    }
  }

  /// Stops following the book (app terminate).
  func stop() {
    watcher?.cancel()
    watcher = nil
  }

  /// One feed check with the current settings. Throws only when the store fails; the daily step counts that.
  func refresh() async throws {
    guard let url = URL(string: settings.priceFeedURL) else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    try await book.refresh(fetcher: fetcher, url: url, feedEnabled: settings.priceFeedEnabled,
                           staleAfterDays: settings.priceStaleAfterDays)
  }

  /// `Refresh now`.
  func refreshNow() async {
    do {
      try await refresh()
    } catch {
      Log.error(.uiError, cat: .ui, msg: "price refresh failed", err: error, ctx: ["view": "price book"])
    }
  }

  /// The override sheet's `Save`: rates typed in USD per 1M tokens. False when a rate does not parse, the input
  /// or output rate is not positive, or the store failed (logged).
  func saveOverride(model: String, input: String, output: String, cacheRead: String, cacheWrite: String) async
    -> Bool {
    let locale = Locale.current
    func optional(_ text: String) -> Int64?? {
      guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .some(nil) }
      return Formatters.rate(fromPerMillion: text, locale: locale).map { .some($0) }
    }
    guard let inputRate = Formatters.rate(fromPerMillion: input, locale: locale),
          let outputRate = Formatters.rate(fromPerMillion: output, locale: locale),
          let readRate = optional(cacheRead), let writeRate = optional(cacheWrite),
          inputRate > 0, outputRate > 0, !model.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    let entry = PriceEntry(input: inputRate, output: outputRate, cacheRead: readRate, cacheWrite: writeRate)
    do {
      try await book.setOverride(model: model, entry: entry)
      return true
    } catch {
      Log.error(.uiError, cat: .ui, msg: "price override not saved", err: error, ctx: ["view": "price book"])
      return false
    }
  }

  /// `−`.
  func removeOverride(model: String) async {
    do {
      try await book.removeOverride(model: model)
    } catch {
      Log.error(.uiError, cat: .ui, msg: "price override not removed", err: error, ctx: ["view": "price book"])
    }
  }

  /// `Reset to feed`.
  func resetToFeed() async {
    do {
      try await book.resetToFeed()
    } catch {
      Log.error(.uiError, cat: .ui, msg: "price overrides not reset", err: error, ctx: ["view": "price book"])
    }
  }

  /// `Resources/prices.bundled.json` and its `.sha256` (14 § Stage 5.1 step 1); nil when either is missing.
  static func bundled() -> PriceBook.Bundled? {
    guard let json = Bundle.main.url(forResource: "prices.bundled", withExtension: "json"),
          let sum = Bundle.main.url(forResource: "prices.bundled", withExtension: "sha256") else { return nil }
    do {
      return PriceBook.Bundled(
        data: try Data(contentsOf: json),
        sha256: try String(contentsOf: sum, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
      )
    } catch {
      Log.warn(.priceParseFailed, cat: .price, msg: "bundled prices unreadable", err: error, ctx: ["bytes": 0])
      return nil
    }
  }
}
