public struct QueryItem: Sendable, Equatable, Hashable {
  public let name: String
  public let value: String

  public init(_ name: String, _ value: String) {
    self.name = name
    self.value = value
  }

  public init(_ name: String, _ value: some CustomStringConvertible & Sendable) {
    self.init(name, String(describing: value))
  }
}
