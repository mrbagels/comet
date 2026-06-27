import Foundation

/// Represents a single URL query item.
public struct QueryItem: Sendable, Equatable, Hashable {
  public let name: String
  public let value: String

  /// Creates a query item from explicit string values.
  public init(_ name: String, _ value: String) {
    self.name = name
    self.value = value
  }

  /// Creates a query item from any losslessly printable value.
  public init(_ name: String, _ value: some CustomStringConvertible & Sendable) {
    self.init(name, String(describing: value))
  }

  /// Creates a query item from an optional value, returning `nil` when the value is absent.
  public init?<Value: CustomStringConvertible & Sendable>(_ name: String, _ value: Value?) {
    guard let value else { return nil }
    self.init(name, String(describing: value))
  }

  /// Creates a query item whose value is `true` or `false`.
  public static func bool(_ name: String, _ value: Bool) -> Self {
    Self(name, value ? "true" : "false")
  }

  /// Creates a query item when `value` is present.
  public static func optional<Value: CustomStringConvertible & Sendable>(
    _ name: String,
    _ value: Value?
  ) -> Self? {
    Self(name, value)
  }

  /// Creates `name=value` when `isEnabled` is true, otherwise returns `nil`.
  public static func flag(
    _ name: String,
    isEnabled: Bool,
    value: String = "true"
  ) -> Self? {
    isEnabled ? Self(name, value) : nil
  }

  /// Creates one query item per value using the same key.
  public static func items<Values: Sequence>(
    _ name: String,
    values: Values
  ) -> [Self] where Values.Element: CustomStringConvertible & Sendable {
    values.map { Self(name, $0) }
  }

  /// Creates a single query item by joining multiple values, returning `nil` for an empty sequence.
  public static func joined<Values: Sequence>(
    _ name: String,
    values: Values,
    separator: String = ","
  ) -> Self? where Values.Element: CustomStringConvertible & Sendable {
    let encodedValues = values.map { String(describing: $0) }
    guard !encodedValues.isEmpty else { return nil }
    return Self(name, encodedValues.joined(separator: separator))
  }

  /// Creates a query item from a date using the requested encoding style.
  public static func date(
    _ name: String,
    _ value: Date,
    style: QueryDateEncodingStyle = .iso8601
  ) -> Self {
    switch style {
    case .iso8601:
      return Self(name, ISO8601DateFormatter().string(from: value))
    case .secondsSince1970:
      return Self(name, Int64(value.timeIntervalSince1970))
    case .millisecondsSince1970:
      return Self(name, Int64((value.timeIntervalSince1970 * 1_000).rounded()))
    }
  }
}

/// Common encodings for date query parameters.
public enum QueryDateEncodingStyle: Sendable, Equatable {
  /// Encodes dates with `ISO8601DateFormatter`.
  case iso8601
  /// Encodes dates as whole seconds since the Unix epoch.
  case secondsSince1970
  /// Encodes dates as whole milliseconds since the Unix epoch.
  case millisecondsSince1970
}
