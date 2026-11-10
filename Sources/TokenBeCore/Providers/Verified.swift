/// Providers whose live responses are recorded (13 § D-verified-providers): each member has
/// `Tests/Fixtures/providers/<p>/RECORDED`, and each marker has its member (`VerifiedProvidersTests`, both ways).
/// Only these are offered in Release builds. Empty until H2/H3 record the first fixtures.
public enum Verified {
  public static let providers: Set<ProviderID> = []
}
