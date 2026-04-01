import Foundation

public struct Path: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
  private let segments: [String]

  public init(_ rawValue: String) {
    self.segments = rawValue
      .split(separator: "/")
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  private init(segments: [String]) {
    self.segments = segments.filter { !$0.isEmpty }
  }

  public var rawValue: String {
    self.segments
      .map(Self.encode(segment:))
      .joined(separator: "/")
  }

  public var description: String {
    self.rawValue
  }

  public static func / (lhs: Path, rhs: String) -> Path {
    Path(
      segments: lhs.segments
        + rhs.split(separator: "/").map(String.init)
    )
  }

  public static func / <T: LosslessStringConvertible>(lhs: Path, rhs: T) -> Path {
    lhs / String(rhs)
  }

  private static func encode(segment: String) -> String {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
  }
}
