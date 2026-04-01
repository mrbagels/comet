import Foundation
import HTTPTypes

public struct BearerTokenMiddleware: Middleware {
  private let tokenProvider: @Sendable () async -> String?

  public init(tokenProvider: @escaping @Sendable () async -> String?) {
    self.tokenProvider = tokenProvider
  }

  public func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest {
    guard let token = await self.tokenProvider() else { return request }
    var headers = request.headers
    headers[.authorization] = "Bearer \(token)"
    return PreparedRequest(
      url: request.url,
      method: request.method,
      headers: headers,
      body: request.body,
      timeout: request.timeout
    )
  }
}
