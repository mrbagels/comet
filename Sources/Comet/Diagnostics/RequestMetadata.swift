import Foundation

/// Human-readable identity for a request as it moves through diagnostics, logs, and fixtures.
public struct RequestMetadata: Sendable, Hashable {
  public var name: String?
  public var tags: [String]
  public var operationID: String?
  public var traceContext: TraceContext?

  public init(
    name: String? = nil,
    tags: [String] = [],
    operationID: String? = nil
  ) {
    self.name = name
    self.tags = tags
    self.operationID = operationID
    self.traceContext = nil
  }

  public init(
    name: String? = nil,
    tags: [String] = [],
    operationID: String? = nil,
    traceContext: TraceContext
  ) {
    self.name = name
    self.tags = tags
    self.operationID = operationID
    self.traceContext = traceContext
  }

  public static let none = Self()

  public var displayName: String? {
    self.name ?? self.operationID
  }

  /// A stable operation label for logs and distributed traces.
  public var operationName: String? {
    self.operationID ?? self.name
  }

  /// The W3C trace ID associated with the request, when one was provided in metadata.
  public var traceID: String? {
    self.traceContext?.traceID
  }
}
