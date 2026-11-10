/// The adapters this build has, and which providers onboarding may offer (14 § Stage 3.3 step 4).
public struct ProviderRegistry: Sendable {
  public let adapters: [ProviderID: any ProviderAdapter]
  public let verified: Set<ProviderID>
  public let isDebug: Bool

  public init(adapters: [any ProviderAdapter], verified: Set<ProviderID> = Verified.providers,
              isDebug: Bool = ProviderRegistry.buildIsDebug) {
    self.adapters = Dictionary(adapters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    self.verified = verified
    self.isDebug = isDebug
  }

  /// True in DEBUG builds.
  public static var buildIsDebug: Bool {
    #if DEBUG
    true
    #else
    false
    #endif
  }

  /// Onboarding's tiles (08 step 1), in 08's order. Release offers only verified providers (D-verified-providers,
  /// R13); DEBUG offers every provider. Both offer only providers with an adapter, so no tile is inert (D6, Q-028).
  public var availableForOnboarding: [ProviderID] {
    Self.available(isDebug: isDebug, verified: verified, adapters: Set(adapters.keys))
  }

  static func available(isDebug: Bool, verified: Set<ProviderID>, adapters: Set<ProviderID>) -> [ProviderID] {
    ProviderID.allCases.filter { adapters.contains($0) && (isDebug || verified.contains($0)) }
  }

  public func adapter(for provider: ProviderID) -> (any ProviderAdapter)? {
    adapters[provider]
  }
}
