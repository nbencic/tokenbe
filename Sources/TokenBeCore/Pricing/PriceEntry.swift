import Foundation

/// One model's rates from the price feed or an override (02 § Price feed, 05 § Price lookup). Rates are integer
/// picodollars per token (1 USD = 10^12): the feed's USD-per-token numbers are converted once, at decode, so no
/// arithmetic on money ever uses a floating-point type (R7, Q-038). 2.5 × 10^-6 USD per token is 2_500_000.
public struct PriceEntry: Sendable, Equatable {
  /// Picodollars (10^-12 USD) per token.
  public typealias Rate = Int64

  /// `input_cost_per_token`
  public var input: Rate?
  /// `output_cost_per_token`
  public var output: Rate?
  /// `cache_read_input_token_cost`
  public var cacheRead: Rate?
  /// `cache_creation_input_token_cost` (the 5-minute write)
  public var cacheWrite: Rate?
  /// `cache_creation_input_token_cost_above_1hr`
  public var cacheWrite1h: Rate?
  /// `litellm_provider`
  public var litellmProvider: String?
  /// `mode`; entries other than `chat` never reach lookup (05).
  public var mode: String?

  public init(input: Rate? = nil, output: Rate? = nil, cacheRead: Rate? = nil, cacheWrite: Rate? = nil,
              cacheWrite1h: Rate? = nil, litellmProvider: String? = nil, mode: String? = "chat") {
    self.input = input
    self.output = output
    self.cacheRead = cacheRead
    self.cacheWrite = cacheWrite
    self.cacheWrite1h = cacheWrite1h
    self.litellmProvider = litellmProvider
    self.mode = mode
  }

  /// The feed keys of 02 that TokenBe reads, also the keys of a `price_override.json` (03).
  public enum Key {
    public static let input = "input_cost_per_token"
    public static let output = "output_cost_per_token"
    public static let cacheRead = "cache_read_input_token_cost"
    public static let cacheWrite = "cache_creation_input_token_cost"
    public static let cacheWrite1h = "cache_creation_input_token_cost_above_1hr"
    public static let litellmProvider = "litellm_provider"
    public static let mode = "mode"
  }

  /// V5: priced only when both the input and the output rate are positive.
  public var isPriced: Bool { (input ?? 0) > 0 && (output ?? 0) > 0 }

  /// An entry from one feed object (a JSON dictionary). Unknown keys are ignored (O-6: the decoder is lenient); a
  /// rate that is not a number is treated as missing.
  public init(feedObject object: [String: Any]) {
    input = Self.rate(object[Key.input])
    output = Self.rate(object[Key.output])
    cacheRead = Self.rate(object[Key.cacheRead])
    cacheWrite = Self.rate(object[Key.cacheWrite])
    cacheWrite1h = Self.rate(object[Key.cacheWrite1h])
    litellmProvider = object[Key.litellmProvider] as? String
    mode = object[Key.mode] as? String
  }

  /// A `price_override.json` (03: the keys of a feed entry).
  public init(json: String) throws(PriceTable.ParseError) {
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    } catch {
      throw .notAnObject
    }
    guard let fields = object as? [String: Any] else { throw .notAnObject }
    self.init(feedObject: fields)
  }

  /// The feed object of this entry, for `price_override.json`. A rate is written as `<picodollars>e-12`, a JSON
  /// number that reads back to the same integer.
  public func feedJSON() -> String {
    var fields: [String] = []
    let rates: [(String, Rate?)] = [(Key.cacheWrite, cacheWrite), (Key.cacheWrite1h, cacheWrite1h),
                                    (Key.cacheRead, cacheRead), (Key.input, input), (Key.output, output)]
    for (key, rate) in rates.sorted(by: { $0.0 < $1.0 }) {
      if let rate { fields.append("\"\(key)\":\(rate)e-12") }
    }
    fields.append("\"\(Key.mode)\":\"chat\"")
    return "{" + fields.joined(separator: ",") + "}"
  }

  /// The only conversion from the feed's floating-point JSON numbers (Q-038): USD per token → picodollars,
  /// rounded to the nearest integer. Booleans and strings are not rates.
  static func rate(_ value: Any?) -> Rate? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let scaled = (number.doubleValue * 1e12).rounded()
    guard scaled.isFinite, abs(scaled) < 9e18 else { return nil }
    return Rate(scaled)
  }
}

/// A parsed snapshot: the `chat` entries by feed key (05: entries with `mode != "chat"` are ignored).
public struct PriceTable: Sendable, Equatable {
  public var entries: [String: PriceEntry]
  /// Chat entries whose `input_cost_per_token` is present (O-6's shape check counts them).
  public var withInputRate: Int

  public init(entries: [String: PriceEntry] = [:]) {
    self.entries = entries
    withInputRate = entries.values.filter { $0.input != nil }.count
  }

  public enum ParseError: Error, Sendable, Equatable {
    /// Not JSON, or not a JSON object at the top level.
    case notAnObject
  }

  /// Parses a LiteLLM document. Non-object values and non-chat entries are skipped one by one, so one odd entry
  /// (such as the feed's `sample_spec`) never fails the snapshot.
  public static func parse(_ data: Data) throws(ParseError) -> PriceTable {
    let root: Any
    do {
      root = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw .notAnObject
    }
    guard let object = root as? [String: Any] else { throw .notAnObject }
    var entries: [String: PriceEntry] = [:]
    for (key, value) in object {
      guard let fields = value as? [String: Any] else { continue }
      let entry = PriceEntry(feedObject: fields)
      guard entry.mode == "chat" else { continue }
      entries[key] = entry
    }
    return PriceTable(entries: entries)
  }

  /// O-6: the shape changed when no chat entry is left, or more than half lost `input_cost_per_token`.
  public var shapeChanged: Bool { entries.isEmpty || withInputRate * 2 < entries.count }
}
