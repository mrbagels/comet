import Foundation

/// Human-readable identity for a request as it moves through diagnostics, logs, and fixtures.
public struct RequestMetadata: Sendable, Hashable {
  public var name: String?
  public var tags: [String]
  public var operationID: String?

  public init(
    name: String? = nil,
    tags: [String] = [],
    operationID: String? = nil
  ) {
    self.name = name
    self.tags = tags
    self.operationID = operationID
  }

  public static let none = Self()

  public var displayName: String? {
    self.name ?? self.operationID
  }
}
