import Foundation

/// Represents a URL path built from safely encoded segments.
public struct Path: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
  private let segments: [String]

  /// Creates a path from a slash-delimited raw string.
  public init(_ rawValue: String) {
    self.segments = rawValue
      .split(separator: "/")
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  /// Creates a path from a string literal.
  public init(stringLiteral value: String) {
    self.init(value)
  }

  private init(segments: [String]) {
    self.segments = segments.filter { !$0.isEmpty }
  }

  /// The percent-encoded path string.
  public var rawValue: String {
    self.segments
      .map(Self.encode(segment:))
      .joined(separator: "/")
  }

  public var description: String {
    self.rawValue
  }

  /// Appends another path segment.
  public static func / (lhs: Path, rhs: String) -> Path {
    Path(
      segments: lhs.segments
        + rhs.split(separator: "/").map(String.init)
    )
  }

  /// Appends a path segment created from a lossless string convertible value.
  public static func / <T: LosslessStringConvertible>(lhs: Path, rhs: T) -> Path {
    lhs / String(rhs)
  }

  private static func encode(segment: String) -> String {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
  }
}
