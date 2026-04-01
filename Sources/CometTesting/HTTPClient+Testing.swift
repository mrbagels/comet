import Foundation
import HTTPTypes
import Comet

public extension HTTPClient {
  /// Creates a client backed by ``MockTransport`` for deterministic tests.
  static func mock(
    baseURL: URL = URL(string: "https://example.com")!,
    handler: @escaping @Sendable (PreparedRequest) async throws(NetworkError) -> RawResponse
  ) -> Self {
    .live(
      configuration: .default(baseURL: baseURL),
      transport: MockTransport(handler: handler)
    )
  }

  /// Creates a client that always succeeds with the encoded value.
  static func succeeding<T: Encodable & Sendable>(
    with value: T,
    baseURL: URL = URL(string: "https://example.com")!,
    statusCode: Int = 200,
    headers: HTTPFields = .init()
  ) -> Self {
    .mock(baseURL: baseURL) { (_: PreparedRequest) throws(NetworkError) -> RawResponse in
      do {
        let data = try ClientConfiguration.defaultJSONEncoder().encode(value)
        return RawResponse(data: data, statusCode: statusCode, headers: headers)
      } catch {
        throw NetworkError.from(error)
      }
    }
  }

  /// Creates a client that always fails with the provided error.
  static func failing(
    baseURL: URL = URL(string: "https://example.com")!,
    with error: NetworkError = .cancelled
  ) -> Self {
    .mock(baseURL: baseURL) { (_: PreparedRequest) throws(NetworkError) -> RawResponse in
      throw error
    }
  }
}
