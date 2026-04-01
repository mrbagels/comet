/// A marker value for endpoints that are expected to return an empty body.
public struct EmptyResponse: Sendable, Equatable {
  /// Creates an empty response marker.
  public init() {}
}
