public enum StatusValidation: Sendable {
  case successCodes
  case exact(Set<Int>)
  case range(ClosedRange<Int>)
  case custom(@Sendable (Int) -> Bool)

  public static func codes(_ codes: Int...) -> Self {
    .exact(Set(codes))
  }

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
