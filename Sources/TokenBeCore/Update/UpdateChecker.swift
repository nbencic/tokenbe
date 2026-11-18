import Foundation

/// A release version: `MAJOR.MINOR.PATCH`, an optional `-prerelease` and `+build` (semver 2.0). A prerelease sorts
/// below its release; prerelease identifiers compare numerically when both are numbers, else as text; build
/// metadata is ignored.
public struct SemVer: Sendable, Equatable, Comparable, CustomStringConvertible {
  public var major: Int
  public var minor: Int
  public var patch: Int
  public var prerelease: [String]

  /// Nil for anything that is not `X.Y.Z[-pre][+build]`; a leading `v` or `V` is stripped (02: `tag_name`).
  public init?(_ text: String) {
    var body = Substring(text.trimmingCharacters(in: .whitespaces))
    if body.first == "v" || body.first == "V" { body = body.dropFirst() }
    if let plus = body.firstIndex(of: "+") { body = body[..<plus] }
    let parts = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
    guard core.count == 3, let major = Int(core[0]), let minor = Int(core[1]), let patch = Int(core[2]),
          major >= 0, minor >= 0, patch >= 0, core.allSatisfy({ $0.allSatisfy(\.isASCII) && !$0.isEmpty }) else {
      return nil
    }
    self.major = major
    self.minor = minor
    self.patch = patch
    prerelease = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : []
    if parts.count == 2, prerelease.isEmpty { return nil }
  }

  public var description: String {
    "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
  }

  public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
    if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
      return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
    switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
    case (true, true), (true, false): return false
    case (false, true): return true
    case (false, false): break
    }
    for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
      switch (Int(left), Int(right)) {
      case let (left?, right?): return left < right
      case (.some, nil): return true
      case (nil, .some): return false
      case (nil, nil): return left < right
      }
    }
    return lhs.prerelease.count < rhs.prerelease.count
  }
}

/// The release object's fields TokenBe reads (02 § Update check).
struct GitHubRelease: Decodable {
  let tagName: String
  let htmlURL: String?

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case htmlURL = "html_url"
  }
}

/// 02 § Update check (14 § Stage 9.4): `GET` GitHub's latest release once a day from the daily activity, and compare
/// its `tag_name` with the bundle version. No download, no install (D-no-sparkle). Logs
/// `update.check_ok {latest, current, newer}` or `update.check_failed {err}` (07).
public struct UpdateChecker: Sendable {
  /// 02's endpoint; the only GitHub API request TokenBe makes.
  public static let endpoint = URL(string: "https://api.github.com/repos/nbencic/tokenbe/releases/latest")
  /// The release pages' prefix: an `html_url` outside it is not opened (Q-058).
  public static let releasesPage = URL(string: "https://github.com/nbencic/tokenbe/releases")
  public static let timeout: TimeInterval = 10

  /// What one check found.
  public enum Outcome: Sendable, Equatable {
    /// `latest` is the release's version (the `v` stripped); `page` its `html_url` when it is a TokenBe release page.
    case checked(latest: String, page: URL?, newer: Bool)
    /// Logged; nothing changes.
    case failed
  }

  /// A non-2xx answer (no release yet is a 404) or a tag that is not a version.
  struct Unexpected: Error, CustomStringConvertible {
    let description: String
  }

  let transport: any HTTPTransport
  let log: EventLog

  public init(transport: any HTTPTransport, logPipeline: LogPipeline? = nil) {
    self.transport = transport
    log = EventLog(pipeline: logPipeline)
  }

  public func check(current: String) async -> Outcome {
    guard let url = Self.endpoint else { return failed(Unexpected(description: "no endpoint")) }
    let response: HTTPResponse
    do {
      response = try await transport.send(HTTPRequest(url: url, headers: ["Accept": "application/vnd.github+json"],
                                                       timeout: Self.timeout))
    } catch {
      return failed(error)
    }
    guard (200..<300).contains(response.status) else {
      return failed(Unexpected(description: "HTTP \(response.status)"))
    }
    let release: GitHubRelease
    do {
      release = try JSONDecoder().decode(GitHubRelease.self, from: response.body)
    } catch {
      return failed(error)
    }
    guard let latest = SemVer(release.tagName) else {
      return failed(Unexpected(description: "tag_name is not a version"))
    }
    let newer = SemVer(current).map { latest > $0 } ?? false
    log.emit(.info, .updateCheckOk, cat: .update, msg: "update check", ctx: [
      "latest": .string(latest.description), "current": .string(current), "newer": .bool(newer)
    ])
    return .checked(latest: latest.description, page: Self.page(release.htmlURL), newer: newer)
  }

  private func failed(_ error: any Error) -> Outcome {
    log.emit(.warn, .updateCheckFailed, cat: .update, msg: "update check failed", err: error)
    return .failed
  }

  /// `html_url` when it is one of TokenBe's release pages, else nil.
  static func page(_ text: String?) -> URL? {
    guard let text, let prefix = releasesPage?.absoluteString, text.hasPrefix(prefix + "/"),
          let url = URL(string: text) else { return nil }
    return url
  }

  /// A release's page from its version, for a version seen in an earlier run (`tb.update.latestSeen`).
  public static func page(version: String) -> URL? {
    releasesPage?.appendingPathComponent("tag").appendingPathComponent("v" + version)
  }

  /// The badge's rule (09): the latest seen release is newer than the bundle and not the one the user skipped.
  /// An unparsable version on either side shows nothing.
  public static func isUpdateAvailable(latestSeen: String, current: String, ignored: String) -> Bool {
    guard let latest = SemVer(latestSeen), let bundle = SemVer(current), latest > bundle else { return false }
    return SemVer(ignored) != latest
  }

  /// 08's "one GET a day": a check already made on this UTC day is not repeated (`Run daily tasks now`).
  public static func isDue(lastCheckedAt: Double, now: Date) -> Bool {
    lastCheckedAt <= 0 || DailyOnce.utcDay(Date(timeIntervalSince1970: lastCheckedAt)) != DailyOnce.utcDay(now)
  }
}
