import Foundation
import HTTPTypes

/// Builds an HTTP request body and any headers implied by that body.
public struct HTTPBody: Sendable {
  /// The concrete body data and headers produced for a specific client configuration.
  public struct Resolved: Sendable {
    public let data: Data?
    public let headers: HTTPFields

    /// Creates a resolved body payload.
    public init(data: Data?, headers: HTTPFields = .init()) {
      self.data = data
      self.headers = headers
    }
  }

  private let resolve: @Sendable (ClientConfiguration) throws(NetworkError) -> Resolved

  /// Creates a request body from custom resolution logic.
  public init(resolve: @escaping @Sendable (ClientConfiguration) throws(NetworkError) -> Resolved) {
    self.resolve = resolve
  }

  /// Represents the absence of a request body.
  public static let none = HTTPBody { _ in
    Resolved(data: nil)
  }

  /// Creates a raw data body with an optional content type.
  public static func data(_ data: Data, contentType: String? = nil) -> Self {
    HTTPBody { (_: ClientConfiguration) throws(NetworkError) -> Resolved in
      var headers = HTTPFields()
      if let contentType {
        headers[.contentType] = contentType
      }
      return Resolved(data: data, headers: headers)
    }
  }

  /// Creates a plain-text body using the provided string encoding.
  public static func text(
    _ string: String,
    encoding: String.Encoding = .utf8,
    contentType: String? = nil
  ) -> Self {
    HTTPBody { (_: ClientConfiguration) throws(NetworkError) -> Resolved in
      guard let data = string.data(using: encoding) else {
        throw NetworkError.encoding("Unable to encode string body using the requested encoding.")
      }

      var headers = HTTPFields()
      headers[.contentType] = contentType ?? Self.defaultTextContentType(for: encoding)
      return Resolved(data: data, headers: headers)
    }
  }

  /// Encodes an `Encodable` value as JSON using either the provided encoder or the client's configured encoder.
  public static func json<T: Encodable & Sendable>(
    _ value: T,
    using makeEncoder: (@Sendable () -> JSONEncoder)? = nil
  ) -> Self {
    HTTPBody { (configuration: ClientConfiguration) throws(NetworkError) -> Resolved in
      do {
        let encoder = (makeEncoder ?? configuration.makeJSONEncoder)()
        return Resolved(
          data: try encoder.encode(value),
          headers: {
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return headers
          }()
        )
      } catch {
        throw NetworkError.encoding(String(describing: error))
      }
    }
  }

  /// Encodes query items using the `application/x-www-form-urlencoded` body format.
  public static func formURLEncoded(_ items: [QueryItem]) -> Self {
    HTTPBody { (_: ClientConfiguration) throws(NetworkError) -> Resolved in
      var components = URLComponents()
      components.queryItems = items.map { URLQueryItem(name: $0.name, value: $0.value) }
      let bodyString = components.percentEncodedQuery ?? ""
      var headers = HTTPFields()
      headers[.contentType] = "application/x-www-form-urlencoded; charset=utf-8"
      return Resolved(data: Data(bodyString.utf8), headers: headers)
    }
  }

  func resolved(using configuration: ClientConfiguration) throws(NetworkError) -> Resolved {
    try self.resolve(configuration)
  }

  private static func defaultTextContentType(for encoding: String.Encoding) -> String {
    switch encoding {
    case .utf8:
      return "text/plain; charset=utf-8"
    case .utf16:
      return "text/plain; charset=utf-16"
    case .utf16BigEndian:
      return "text/plain; charset=utf-16be"
    case .utf16LittleEndian:
      return "text/plain; charset=utf-16le"
    case .utf32:
      return "text/plain; charset=utf-32"
    case .utf32BigEndian:
      return "text/plain; charset=utf-32be"
    case .utf32LittleEndian:
      return "text/plain; charset=utf-32le"
    default:
      return "text/plain"
    }
  }
}
