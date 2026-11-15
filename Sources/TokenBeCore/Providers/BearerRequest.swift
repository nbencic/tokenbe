import Foundation

/// One HTTPS `GET` of a host and path with 02's `Authorization: Bearer <key>` header, for the providers whose API is a
/// single key-authenticated endpoint (DeepSeek, xAI). The transport adds 02's User-Agent. A non-2xx status becomes
/// its `PollError` (04).
enum BearerRequest {
  static func get(host: String, path: String, provider: ProviderID, key: String,
                  transport: any HTTPTransport) async throws(PollError) -> HTTPResponse {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = path
    guard let url = components.url else { throw .providerRule("\(provider.rawValue)_bad_url \(path)") }
    let request = HTTPRequest(url: url, headers: ["Authorization": "Bearer \(key)", "Accept": "application/json"])
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
