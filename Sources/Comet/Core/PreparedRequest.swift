import Foundation
import HTTPTypes

/// The fully resolved request passed to transports and middleware.
public struct PreparedRequest: Sendable {
  public let url: URL
  public let method: HTTPMethod
  public let headers: HTTPFields
  public let body: Data?
  public let timeout: Duration

  /// Creates a prepared request from concrete transport-ready values.
  public init(
    url: URL,
    method: HTTPMethod,
    headers: HTTPFields = .init(),
    body: Data? = nil,
    timeout: Duration
  ) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
    self.timeout = timeout
  }

  /// Bridges the prepared request back to ``Foundation/URLRequest`` for transport implementations that need it.
  public var urlRequest: URLRequest {
    var request = URLRequest(url: self.url)
    request.httpMethod = self.method.rawValue
    request.httpBody = self.body
    request.timeoutInterval = self.timeout.timeInterval
    request.allHTTPHeaderFields = self.headers.combinedForFoundation
    return request
  }
}
