import Foundation
import HTTPTypes

/// The raw HTTP response returned by a transport before status validation and decoding.
public struct RawResponse: Sendable {
  public let data: Data
  public let statusCode: Int
  public let headers: HTTPFields

  /// Creates a raw response from response data, status code, and headers.
  public init(data: Data, statusCode: Int, headers: HTTPFields = .init()) {
    self.data = data
    self.statusCode = statusCode
    self.headers = headers
  }
}
