import Foundation
import HTTPTypes

/// Adds an `Authorization: Bearer ...` header when a token is available.
public struct BearerTokenMiddleware: Middleware {
  private let tokenProvider: @Sendable () async -> String?

  /// Creates auth middleware backed by an async token provider.
  public init(tokenProvider: @escaping @Sendable () async -> String?) {
    self.tokenProvider = tokenProvider
  }

  /// Adds the latest bearer token to the outgoing request when one is available.
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
