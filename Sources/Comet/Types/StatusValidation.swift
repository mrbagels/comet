/// Defines which HTTP status codes should be treated as successful for a request.
public enum StatusValidation: Sendable {
  case successCodes
  case exact(Set<Int>)
  case range(ClosedRange<Int>)
  case custom(@Sendable (Int) -> Bool)

  /// Treats the provided status codes as successful.
  public static func codes(_ codes: Int...) -> Self {
    .exact(Set(codes))
  }

  /// Treats any 2xx response or `304 Not Modified` as successful.
  public static let successOrNotModified: Self = .custom { statusCode in
    (200..<300).contains(statusCode) || statusCode == 304
  }

  /// Treats 2xx and 3xx responses as successful.
  public static let successAndRedirects: Self = .range(200...399)

  /// Treats no-content responses as successful.
  public static let noContent: Self = .exact([204, 205])

  /// Returns whether the provided status code satisfies this validation rule.
  public func contains(_ statusCode: Int) -> Bool {
    switch self {
    case .successCodes:
      return (200..<300).contains(statusCode)
    case .exact(let codes):
      return codes.contains(statusCode)
    case .range(let range):
      return range.contains(statusCode)
    case .custom(let validate):
      return validate(statusCode)
    }
  }
}
