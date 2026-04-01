import Foundation
import HTTPTypes

public struct URLSessionTransport: HTTPTransport, Sendable {
  private let session: URLSession

  public init(configuration: URLSessionConfiguration = .default) {
    self.session = URLSession(configuration: configuration)
  }

  public init(session: URLSession) {
    self.session = session
  }

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
