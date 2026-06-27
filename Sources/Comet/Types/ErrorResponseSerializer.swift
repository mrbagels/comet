import Foundation
import HTTPTypes

/// Converts an unsuccessful ``RawResponse`` into a typed error payload.
public struct ErrorResponseSerializer<Value: Sendable>: Sendable {
  public let serialize: @Sendable (RawResponse, ClientConfiguration) throws(NetworkError) -> Value

  /// Creates a serializer from custom error-response transformation logic.
  public init(
    serialize: @escaping @Sendable (RawResponse, ClientConfiguration) throws(NetworkError) -> Value
  ) {
    self.serialize = serialize
  }

  /// Decodes a JSON error response using either the provided decoder factory or the client's configured decoder.
  public static func json<T: Decodable & Sendable>(
    _ type: T.Type,
    using makeDecoder: (@Sendable () -> JSONDecoder)? = nil
  ) -> ErrorResponseSerializer<T> {
    ErrorResponseSerializer<T> { (response: RawResponse, configuration: ClientConfiguration) throws(NetworkError) -> T in
      do {
        let decoder = (makeDecoder ?? configuration.makeJSONDecoder)()
        return try decoder.decode(T.self, from: response.data)
      } catch let error as DecodingError {
        throw NetworkError.decoding(error)
      } catch {
        throw NetworkError.from(error)
      }
    }
  }

  /// Returns the error response body as raw ``Foundation/Data``.
  public static var data: ErrorResponseSerializer<Data> {
    ErrorResponseSerializer<Data> { response, _ in
      response.data
    }
  }

  /// Returns the error response body as text, respecting the response charset when available.
  public static func string(
    encoding: String.Encoding? = nil,
    fallbackEncoding: String.Encoding = .utf8
  ) -> ErrorResponseSerializer<String> {
    ErrorResponseSerializer<String> { (response: RawResponse, _: ClientConfiguration) throws(NetworkError) -> String in
      let resolvedEncoding = encoding ?? response.headers.suggestedTextEncoding ?? fallbackEncoding
      guard let string = String(data: response.data, encoding: resolvedEncoding) else {
        throw NetworkError.decoding(
          DecodingError.dataCorrupted(
            .init(
              codingPath: [],
              debugDescription: "Unable to decode string using \(resolvedEncoding)"
            )
          )
        )
      }
      return string
    }
  }

  /// Returns the error response body as text using a fixed encoding.
  public static func string(
    encoding: String.Encoding
  ) -> ErrorResponseSerializer<String> {
    self.string(encoding: Optional(encoding), fallbackEncoding: encoding)
  }

  /// Builds a serializer from custom transformation logic that only needs the raw response.
  public static func custom<T: Sendable>(
    _ serialize: @escaping @Sendable (RawResponse) throws(NetworkError) -> T
  ) -> ErrorResponseSerializer<T> {
    ErrorResponseSerializer<T> { (response: RawResponse, _: ClientConfiguration) throws(NetworkError) -> T in
      try serialize(response)
    }
  }
}

/// Captures a decoded domain error together with the raw HTTP failure.
public struct DecodedErrorResponse<Body: Sendable>: Sendable {
  public let statusCode: Int
  public let body: Body
  public let rawBody: Data
  public let headers: HTTPFields
  public let networkError: NetworkError

  /// Creates a decoded error response from the raw failure and decoded body.
  public init(
    statusCode: Int,
    body: Body,
    rawBody: Data,
    headers: HTTPFields,
    networkError: NetworkError
  ) {
    self.statusCode = statusCode
    self.body = body
    self.rawBody = rawBody
    self.headers = headers
    self.networkError = networkError
  }
}

/// The typed error surface used when a request opts into domain error decoding.
public enum APIClientError<ErrorBody: Sendable>: Error, Sendable {
  /// An unsuccessful HTTP response whose body decoded into the request's domain error type.
  case api(DecodedErrorResponse<ErrorBody>)
  /// A transport, validation, request-building, or success-response decoding failure.
  case network(NetworkError)
  /// An unsuccessful HTTP response whose body could not be decoded into the request's domain error type.
  case errorResponseDecodingFailed(networkError: NetworkError, decodingError: NetworkError)
}

public extension APIClientError {
  /// The raw network failure associated with this error.
  var networkError: NetworkError {
    switch self {
    case .api(let response):
      response.networkError
    case .network(let error):
      error
    case .errorResponseDecodingFailed(let networkError, _):
      networkError
    }
  }

  /// The decoded domain error body, when one was available.
  var decodedErrorBody: ErrorBody? {
    guard case .api(let response) = self else { return nil }
    return response.body
  }

  /// The HTTP status code for unsuccessful HTTP responses.
  var statusCode: Int? {
    self.networkError.statusCode
  }

  /// The raw HTTP response body for unsuccessful HTTP responses.
  var bodyData: Data? {
    self.networkError.bodyData
  }

  /// The response headers for unsuccessful HTTP responses.
  var responseHeaders: HTTPFields? {
    self.networkError.responseHeaders
  }
}

extension APIClientError: LocalizedError, CustomStringConvertible {
  public var errorDescription: String? {
    self.description
  }

  public var description: String {
    switch self {
    case .api(let response):
      return "HTTP \(response.statusCode): \(response.body)"
    case .network(let error):
      return error.debugSummary
    case .errorResponseDecodingFailed(let networkError, let decodingError):
      return "\(networkError.debugSummary) (error body decoding failed: \(decodingError.debugSummary))"
    }
  }
}
