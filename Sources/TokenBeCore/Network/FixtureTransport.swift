#if DEBUG
import Foundation

/// A fixture file (11 § Fixtures, Q-026): `{"status": 429, "headers": {"Retry-After": "12"}, "body": <JSON>}`.
/// `body` is the provider's JSON exactly as 02 describes it; `status` and `headers` carry what a 4xx/5xx case
/// needs. `headers` may be omitted. Shared by `FixtureTransport` and the test target's `StubTransport`.
public struct FixtureEnvelope: Sendable, Equatable {
  public var response: HTTPResponse

  public enum LoadError: Error, Sendable, Equatable {
    case unreadable(String)
    case shape(String)
  }

  public static func load(_ url: URL) throws(LoadError) -> HTTPResponse {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw .unreadable(url.lastPathComponent)
    }
    return try decode(data, name: url.lastPathComponent)
  }

  public static func decode(_ data: Data, name: String) throws(LoadError) -> HTTPResponse {
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw .shape("\(name): not JSON")
    }
    guard let envelope = object as? [String: Any], let status = envelope["status"] as? Int,
          let body = envelope["body"] else {
      throw .shape("\(name): needs \"status\" (number) and \"body\"")
    }
    guard let headers = (envelope["headers"] ?? [String: String]()) as? [String: String] else {
      throw .shape("\(name): \"headers\" must map strings to strings")
    }
    let bodyData: Data
    do {
      bodyData = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed, .sortedKeys])
    } catch {
      throw .shape("\(name): body is not serializable")
    }
    return HTTPResponse(status: status, headers: headers, body: bodyData)
  }
}

/// DEBUG builds with `tb.debug.fixtureMode` (09): answers requests from `Tests/Fixtures/providers` instead of the
/// network (14 § Stage 3.1 step 5). Each route maps `(method, host + path)` to a provider and an endpoint; the
/// file is `<provider>/<endpoint>.<case>.recorded.json`, else `.synthetic.json`. The case is `ok` unless `cases`
/// names another for that endpoint (`"openai/usage_completions": "empty"`). Adapters add their routes (3.4).
public struct FixtureTransport: HTTPTransport {
  public struct Route: Sendable, Equatable {
    public var method: String
    /// `api.openai.com/v1/organization/usage/completions`: host and path, no query.
    public var hostPath: String
    public var provider: ProviderID
    public var endpoint: String

    public init(method: String = "GET", hostPath: String, provider: ProviderID, endpoint: String) {
      self.method = method
      self.hostPath = hostPath
      self.provider = provider
      self.endpoint = endpoint
    }
  }

  /// Every adapter's routes, added with the adapter (3.4 onward); empty until then.
  public static let knownRoutes: [Route] = []

  public let root: URL
  public let routes: [Route]
  public let cases: [String: String]

  public init(root: URL = FixtureTransport.sourceTreeRoot(), routes: [Route], cases: [String: String] = [:]) {
    self.root = root
    self.routes = routes
    self.cases = cases
  }

  /// `Tests/Fixtures/providers` of the source tree this DEBUG build was compiled from. `#filePath` is read here,
  /// inside the function, so it names this file and not the caller's (PM-2.1-1).
  public static func sourceTreeRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Tests/Fixtures/providers", isDirectory: true)
  }

  public func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
    let hostPath = (request.url.host() ?? "") + request.url.path()
    guard let route = routes.first(where: { $0.method == request.method && $0.hostPath == hostPath }) else {
      throw .noFixture("\(request.method) \(hostPath)")
    }
    let key = "\(route.provider.rawValue)/\(route.endpoint)"
    let name = "\(route.endpoint).\(cases[key] ?? "ok")"
    let folder = root.appendingPathComponent(route.provider.rawValue, isDirectory: true)
    for kind in ["recorded", "synthetic"] {
      let file = folder.appendingPathComponent("\(name).\(kind).json")
      guard FileManager.default.fileExists(atPath: file.path) else { continue }
      do {
        return try FixtureEnvelope.load(file)
      } catch {
        throw .noFixture("\(key): \(error)")
      }
    }
    throw .noFixture("\(key): no \(name).recorded.json or \(name).synthetic.json")
  }
}
#endif

/// The transport for a run (09 `tb.debug.fixtureMode`): fixtures in DEBUG when the setting is on, otherwise the
/// network. Release builds ignore the setting. Wired into `AppEnvironment` with the first adapter (Q-026).
public enum Transports {
  public static func make(fixtureMode: Bool, version: String) -> any HTTPTransport {
    #if DEBUG
    if fixtureMode {
      return FixtureTransport(routes: FixtureTransport.knownRoutes)
    }
    #endif
    return URLSessionTransport(version: version)
  }
}
