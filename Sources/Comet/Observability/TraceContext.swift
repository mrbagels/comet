import Foundation
import HTTPTypes

/// A W3C trace context that can be propagated with the `traceparent` HTTP header.
public struct TraceContext: Sendable, Hashable {
  /// The HTTP header name used for W3C trace propagation.
  public static let traceparentHeaderName = HTTPField.Name("traceparent")!

  public let version: String
  public let traceID: String
  public let parentID: String
  public let flags: String

  /// Creates a trace context from validated W3C `traceparent` fields.
  public init?(
    traceID: String,
    parentID: String,
    flags: String = "00",
    version: String = "00"
  ) {
    let normalizedVersion = version.lowercased()
    let normalizedTraceID = traceID.lowercased()
    let normalizedParentID = parentID.lowercased()
    let normalizedFlags = flags.lowercased()

    guard Self.isValidVersion(normalizedVersion) else { return nil }
    guard Self.isValidTraceID(normalizedTraceID) else { return nil }
    guard Self.isValidParentID(normalizedParentID) else { return nil }
    guard Self.isValidFlags(normalizedFlags) else { return nil }

    self.version = normalizedVersion
    self.traceID = normalizedTraceID
    self.parentID = normalizedParentID
    self.flags = normalizedFlags
  }

  /// Parses a W3C `traceparent` header value.
  public init?(traceparent: String) {
    let parts = traceparent.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 4 else { return nil }
    self.init(
      traceID: parts[1],
      parentID: parts[2],
      flags: parts[3],
      version: parts[0]
    )
  }

  /// Creates a deterministic trace context from a Comet request ID.
  public static func generated(
    requestID: UUID = UUID(),
    sampled: Bool = true
  ) -> Self {
    var traceID = requestID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    if traceID.allSatisfy({ $0 == "0" }) {
      traceID = "00000000000000000000000000000001"
    }

    var parentID = String(traceID.suffix(16))
    if parentID.allSatisfy({ $0 == "0" }) {
      parentID = "0000000000000001"
    }

    return Self(
      traceID: traceID,
      parentID: parentID,
      flags: sampled ? "01" : "00"
    )!
  }

  /// The exact value to write into a W3C `traceparent` header.
  public var traceparent: String {
    "\(self.version)-\(self.traceID)-\(self.parentID)-\(self.flags)"
  }

  /// Whether the sampled bit is set in the trace flags.
  public var isSampled: Bool {
    guard let value = UInt8(self.flags, radix: 16) else { return false }
    return value & 0x01 == 0x01
  }

  private static func isValidVersion(_ value: String) -> Bool {
    value.count == 2
      && value != "ff"
      && value.allSatisfy(\.isLowercaseHexDigit)
  }

  private static func isValidTraceID(_ value: String) -> Bool {
    value.count == 32
      && !value.allSatisfy { $0 == "0" }
      && value.allSatisfy(\.isLowercaseHexDigit)
  }

  private static func isValidParentID(_ value: String) -> Bool {
    value.count == 16
      && !value.allSatisfy { $0 == "0" }
      && value.allSatisfy(\.isLowercaseHexDigit)
  }

  private static func isValidFlags(_ value: String) -> Bool {
    value.count == 2 && value.allSatisfy(\.isLowercaseHexDigit)
  }
}

extension PreparedRequest {
  var propagatedTraceContext: TraceContext? {
    if let traceparent = self.headers[TraceContext.traceparentHeaderName] {
      return TraceContext(traceparent: traceparent)
    }
    return self.metadata.traceContext
  }
}

private extension Character {
  var isLowercaseHexDigit: Bool {
    ("0"..."9").contains(self) || ("a"..."f").contains(self)
  }
}
