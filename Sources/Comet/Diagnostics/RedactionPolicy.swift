import Foundation

/// Describes how Comet redacts sensitive data before it is logged, exported, or recorded.
public struct RedactionPolicy: Sendable {
  public static let defaultSensitiveHeaders: Set<String> = [
    "authorization",
    "cookie",
    "set-cookie",
    "x-api-key",
    "x-auth-token",
    "api-key"
  ]

  public static let safeDefault = Self()

  public static let disabled = Self(redactedHeaders: [])

  public var redactedHeaders: Set<String>
  public var redactedText: String
  public var redactedBody: Data

  private let redactRequestBody: @Sendable (PreparedRequest) -> Bool
  private let redactResponseBody: @Sendable (RawResponse) -> Bool

  /// Creates a redaction policy for sensitive headers and optional request/response bodies.
  public init(
    redactedHeaders: Set<String> = Self.defaultSensitiveHeaders,
    redactedText: String = "<redacted>",
    redactedBody: Data = Data("<redacted>".utf8),
    redactRequestBody: @escaping @Sendable (PreparedRequest) -> Bool = { _ in false },
    redactResponseBody: @escaping @Sendable (RawResponse) -> Bool = { _ in false }
  ) {
    self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
    self.redactedText = redactedText
    self.redactedBody = redactedBody
    self.redactRequestBody = redactRequestBody
    self.redactResponseBody = redactResponseBody
  }

  public func redacts(headerName: String) -> Bool {
    self.redactedHeaders.contains {
      $0.caseInsensitiveCompare(headerName) == .orderedSame
    }
  }

  public func redactedHeaderValue(
    name: String,
    value: String
  ) -> String {
    self.redacts(headerName: name) ? self.redactedText : value
  }

  public func recordedRequestBody(for request: PreparedRequest) -> (data: Data?, wasRedacted: Bool) {
    guard request.body != nil, self.redactRequestBody(request) else {
      return (request.body, false)
    }
    return (self.redactedBody, true)
  }

  public func recordedResponseBody(for response: RawResponse) -> (data: Data, wasRedacted: Bool) {
    guard self.redactResponseBody(response) else {
      return (response.data, false)
    }
    return (self.redactedBody, true)
  }
}
