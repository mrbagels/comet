import Foundation
import HTTPTypes

public struct RawResponse: Sendable {
  public let data: Data
  public let statusCode: Int
  public let headers: HTTPFields

  public init(data: Data, statusCode: Int, headers: HTTPFields = .init()) {
    self.data = data
    self.statusCode = statusCode
    self.headers = headers
  }
}
