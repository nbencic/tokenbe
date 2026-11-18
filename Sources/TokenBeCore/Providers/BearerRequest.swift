import Foundation

/// One HTTPS request to a host and path with 02's `Authorization: Bearer <key>` header, for the providers whose API is
/// a few key-authenticated endpoints (DeepSeek, xAI). `get` sends no body; `post` sends a JSON body (xAI's usage
/// query). The transport adds 02's User-Agent. A non-2xx status becomes its `PollError` (04).
enum BearerRequest {
  /// Where a request goes: 02's host and path, and the provider (for its error).
  struct Target {
    var host: String
    var path: String
    var provider: ProviderID
  }

  static func get(host: String, path: String, provider: ProviderID, key: String,
                  transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    try await send("GET", Target(host: host, path: path, provider: provider), key: key, body: nil, transport: transport)
  }

  static func post(_ target: Target, key: String, json: Data,
                   transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    try await send("POST", target, key: key, body: json, transport: transport)
  }

  private static func send(_ method: String, _ target: Target, key: String, body: Data?,
                           transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    var components = URLComponents()
    components.scheme = "https"
    components.host = target.host
    components.path = target.path
    guard let url = components.url else {
      throw .providerRule("\(target.provider.rawValue)_bad_url \(target.path)")
    }
    var headers = ["Authorization": "Bearer \(key)", "Accept": "application/json"]
    if body != nil { headers["Content-Type"] = "application/json" }
    let request = HTTPRequest(method: method, url: url, headers: headers, body: body)
    let response: HTTPResponse
    do {
      response = try await transport.send(request)
    } catch {
      throw PollError.from(error)
    }
    if let failure = PollError.from(response) { throw failure }
    return response
  }
}
