import Foundation
import Comet

/// An in-memory transport for deterministic tests and examples.
public struct MockTransport: HTTPTransport, Sendable {
  /// Identifies a mocked route by method, path, and optional query string.
  public struct RequestKey: Hashable, Sendable {
    public let method: HTTPMethod?
    public let path: String
    public let query: String?

    public init(
      method: HTTPMethod? = nil,
      path: String,
      query: String? = nil
    ) {
      self.method = method
      self.path = path
      self.query = query
    }

    init(request: PreparedRequest) {
      self.init(
        method: request.method,
        path: request.url.path,
        query: URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
      )
    }
  }

  public let handler: @Sendable (PreparedRequest) async throws(NetworkError) -> RawResponse

  /// Creates a mock transport from an async request handler.
  public init(
    handler: @escaping @Sendable (PreparedRequest) async throws(NetworkError) -> RawResponse
  ) {
    self.handler = handler
  }

  /// Sends a request through the configured in-memory handler.
  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    try await self.handler(request)
  }

  /// Creates a mock transport backed by simple path-to-response mappings.
  public static func responses(_ responses: [String: RawResponse]) -> Self {
    Self { (request: PreparedRequest) throws(NetworkError) -> RawResponse in
      guard let response = responses[request.url.path] else {
        throw NetworkError.invalidRequest("No mocked response registered for path \(request.url.path).")
      }
      return response
    }
  }

  /// Creates a mock transport backed by method, path, and query-aware route matching.
  public static func routes(_ responses: [RequestKey: RawResponse]) -> Self {
    Self { (request: PreparedRequest) throws(NetworkError) -> RawResponse in
      let key = RequestKey(request: request)
      if let response = responses[key] {
        return response
      }

      let methodAgnosticKey = RequestKey(path: key.path, query: key.query)
      if let response = responses[methodAgnosticKey] {
        return response
      }

      throw NetworkError.invalidRequest(
        "No mocked response registered for \(request.method.rawValue) \(request.url.path)\(key.query.map { "?\($0)" } ?? "")."
      )
    }
  }
}
