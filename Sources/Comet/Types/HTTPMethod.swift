/// Represents an HTTP method while preserving support for custom verbs.
public struct HTTPMethod: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
  public let rawValue: String

  /// Creates an HTTP method, normalizing the raw value to uppercase.
  public init(rawValue: String) {
    self.rawValue = rawValue.uppercased()
  }

  /// Creates an HTTP method from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public var description: String {
    self.rawValue
  }

  public static let get: Self = "GET"
  public static let post: Self = "POST"
  public static let put: Self = "PUT"
  public static let patch: Self = "PATCH"
  public static let delete: Self = "DELETE"
  public static let head: Self = "HEAD"
  public static let options: Self = "OPTIONS"
}
