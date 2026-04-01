import Foundation

/// Converts a ``RawResponse`` into a typed value after transport, middleware, and status validation.
public struct ResponseSerializer<Value: Sendable>: Sendable {
  public let serialize: @Sendable (RawResponse, ClientConfiguration) throws(NetworkError) -> Value

  /// Creates a serializer from custom response transformation logic.
  public init(
    serialize: @escaping @Sendable (RawResponse, ClientConfiguration) throws(NetworkError) -> Value
  ) {
    self.serialize = serialize
  }

  /// Decodes a JSON response using either the provided decoder factory or the client's configured decoder.
  public static func json<T: Decodable & Sendable>(
    _ type: T.Type,
    using makeDecoder: (@Sendable () -> JSONDecoder)? = nil
  ) -> ResponseSerializer<T> {
    ResponseSerializer<T> { (response: RawResponse, configuration: ClientConfiguration) throws(NetworkError) -> T in
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

  /// Returns the response body as raw ``Foundation/Data``.
  public static var data: ResponseSerializer<Data> {
    ResponseSerializer<Data> { response, _ in
      response.data
    }
  }

  /// Returns the response body as text, respecting the response charset when available.
  public static func string(
    encoding: String.Encoding? = nil,
    fallbackEncoding: String.Encoding = .utf8
  ) -> ResponseSerializer<String> {
    ResponseSerializer<String> { (response: RawResponse, _: ClientConfiguration) throws(NetworkError) -> String in
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

  /// Returns the response body as text using a fixed encoding.
  public static func string(
    encoding: String.Encoding
  ) -> ResponseSerializer<String> {
    self.string(encoding: Optional(encoding), fallbackEncoding: encoding)
  }

  /// Validates that the response body is empty and returns ``EmptyResponse``.
  public static var empty: ResponseSerializer<EmptyResponse> {
    ResponseSerializer<EmptyResponse> { (response: RawResponse, _: ClientConfiguration) throws(NetworkError) -> EmptyResponse in
      guard response.data.isEmpty else {
        throw NetworkError.decoding(
          DecodingError.dataCorrupted(
            .init(
              codingPath: [],
              debugDescription: "Expected an empty response body."
            )
          )
        )
      }
      return EmptyResponse()
    }
  }

  /// Builds a serializer from custom transformation logic that only needs the raw response.
  public static func custom<T: Sendable>(
    _ serialize: @escaping @Sendable (RawResponse) throws(NetworkError) -> T
  ) -> ResponseSerializer<T> {
    ResponseSerializer<T> { (response: RawResponse, _: ClientConfiguration) throws(NetworkError) -> T in
      try serialize(response)
    }
  }
}
