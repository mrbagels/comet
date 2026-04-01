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
}
