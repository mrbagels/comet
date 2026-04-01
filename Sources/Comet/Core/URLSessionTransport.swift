import Foundation
import HTTPTypes

/// The shipped live transport backed by ``Foundation/URLSession``.
public struct URLSessionTransport: HTTPTransport, Sendable {
  private let session: URLSession

  /// Creates a live transport backed by a new ``URLSession`` with the provided configuration.
  public init(configuration: URLSessionConfiguration = .default) {
    self.session = URLSession(configuration: configuration)
  }

  /// Creates a live transport backed by an existing ``URLSession``.
  public init(session: URLSession) {
    self.session = session
  }

  /// Sends a prepared request through ``URLSession`` and converts the result to ``RawResponse``.
  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    do {
      let (data, response) = try await self.session.data(for: request.urlRequest)
      guard let response = response as? HTTPURLResponse else {
        throw NetworkError.invalidRequest("Expected an HTTPURLResponse from transport.")
      }
      return RawResponse(
        data: data,
        statusCode: response.statusCode,
        headers: HTTPFields(response.allHeaderFields)
      )
    } catch {
      throw .from(error)
    }
  }
}
