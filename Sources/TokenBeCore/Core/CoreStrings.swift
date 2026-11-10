/// User-visible copy produced in Core (12 § R9): the probe's human messages, which onboarding (08 step 2) and the
/// Sources strip (08 `HP-0`) show instead of raw JSON. The App's `Strings.swift` holds every other string.
public enum CoreStrings {
  public enum OpenAI {
    /// 02 § openai Errors, verbatim: a key that is not an admin key gets 401 on `/v1/organization/*`.
    public static let notAdminKey =
      "This is not an Admin key. Create one at platform.openai.com → Settings → Organization → Admin keys (Organization Owner only)."
    /// 02 names 403 "missing scope" without copy; authored (Q-029).
    public static let missingScope =
      "This Admin key is missing a permission TokenBe needs. Check its permissions at platform.openai.com → Settings → Organization → Admin keys."
  }

  /// `Test` with no Keychain item for the account; authored (Q-030), pointing at 08's `Replace key…`.
  public static let keyMissing = "The key is missing from the Keychain. Use Replace key… to add it again."

  // The rest is authored (Q-029): 02 § Errors gives no copy for these classes.

  /// 429.
  public static func rateLimited(_ provider: String) -> String {
    "\(provider) is limiting requests right now. Try again in a minute."
  }

  /// 5xx.
  public static func serverError(_ provider: String, status: Int) -> String {
    "\(provider) returned a server error (HTTP \(status)). Try again later."
  }

  /// DNS, timeout, offline.
  public static func unreachable(_ provider: String) -> String {
    "Could not reach \(provider). Check your internet connection and try again."
  }

  /// A 2xx body TokenBe could not read.
  public static func unexpectedResponse(_ provider: String) -> String {
    "\(provider) answered in a format TokenBe does not recognize."
  }

  /// Any other status (3xx, other 4xx).
  public static func unexpectedStatus(_ provider: String, status: Int) -> String {
    "\(provider) answered with HTTP \(status)."
  }
}
