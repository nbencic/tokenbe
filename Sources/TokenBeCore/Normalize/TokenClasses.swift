/// The only usage shape the rest of the app sees (05 § TokenClasses). Integer tokens, never `Double` (R7).
public struct TokenClasses: Sendable, Equatable {
  public var inputUncached: Int64 = 0
  public var cacheWrite5m: Int64 = 0
  public var cacheWrite1h: Int64 = 0
  public var cacheRead: Int64 = 0
  /// EXCLUDES reasoning when the provider reports reasoning separately.
  public var output: Int64 = 0
  public var reasoning: Int64 = 0
  public var requests: Int64 = 0

  public init(inputUncached: Int64 = 0, cacheWrite5m: Int64 = 0, cacheWrite1h: Int64 = 0, cacheRead: Int64 = 0,
              output: Int64 = 0, reasoning: Int64 = 0, requests: Int64 = 0) {
    self.inputUncached = inputUncached
    self.cacheWrite5m = cacheWrite5m
    self.cacheWrite1h = cacheWrite1h
    self.cacheRead = cacheRead
    self.output = output
    self.reasoning = reasoning
    self.requests = requests
  }

  /// Every token class summed (requests excluded): the quantity V2 compares (04 § Invariants).
  public var tokens: Int64 {
    inputUncached + cacheWrite5m + cacheWrite1h + cacheRead + output + reasoning
  }

  public static func + (lhs: TokenClasses, rhs: TokenClasses) -> TokenClasses {
    TokenClasses(
      inputUncached: lhs.inputUncached + rhs.inputUncached, cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
      cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h, cacheRead: lhs.cacheRead + rhs.cacheRead,
      output: lhs.output + rhs.output, reasoning: lhs.reasoning + rhs.reasoning, requests: lhs.requests + rhs.requests
    )
  }

  public static func += (lhs: inout TokenClasses, rhs: TokenClasses) {
    lhs = lhs + rhs
  }
}

extension UsageBucketRecord {
  /// The row's token classes.
  public var classes: TokenClasses {
    TokenClasses(inputUncached: inputUncached, cacheWrite5m: cacheWrite5m, cacheWrite1h: cacheWrite1h,
                 cacheRead: cacheRead, output: output, reasoning: reasoning, requests: requests)
  }
}
