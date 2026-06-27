import Foundation
import HTTPTypes

/// Controls how a generated cURL command is formatted.
public enum CURLCommandStyle: Sendable, Equatable {
  /// Formats each argument on its own continued shell line.
  case multiline
  /// Formats the full command on one shell line.
  case compact
}

/// Controls how request bodies are rendered in generated cURL commands.
public enum CURLCommandBodyFormatting: Sendable, Equatable {
  /// Uses the original request body bytes whenever they can be decoded as UTF-8.
  case original
  /// Pretty-prints JSON object and array bodies, falling back to the original body for non-JSON content.
  case prettyPrintedJSON
}

/// Configures generated cURL command output.
public struct CURLCommandOptions: Sendable, Equatable {
  public var style: CURLCommandStyle
  public var bodyFormatting: CURLCommandBodyFormatting

  /// Creates cURL output options.
  public init(
    style: CURLCommandStyle = .multiline,
    bodyFormatting: CURLCommandBodyFormatting = .original
  ) {
    self.style = style
    self.bodyFormatting = bodyFormatting
  }
}

extension PreparedRequest {
  public func curlCommand(redactionPolicy: RedactionPolicy? = nil) -> String {
    self.curlCommand(redactionPolicy: redactionPolicy, options: .init())
  }

  public func curlCommand(style: CURLCommandStyle) -> String {
    self.curlCommand(options: .init(style: style))
  }

  public func curlCommand(redactionPolicy: RedactionPolicy?, style: CURLCommandStyle) -> String {
    self.curlCommand(redactionPolicy: redactionPolicy, options: .init(style: style))
  }

  public func curlCommand(options: CURLCommandOptions) -> String {
    self.curlCommand(redactionPolicy: nil, options: options)
  }

  public func curlCommand(redactionPolicy: RedactionPolicy?, options: CURLCommandOptions) -> String {
    let policy = redactionPolicy ?? self.redactionPolicy
    var parts = ["curl"]
    parts.append("-X \(self.method.rawValue.shellQuoted)")
    for field in self.headers {
      let name = field.name.canonicalName
      let value = policy.redactedHeaderValue(name: name, value: field.value)
      parts.append("-H \("\(name): \(value)".shellQuoted)")
    }

    let body = policy.recordedRequestBody(for: self)
    if let data = body.data, !data.isEmpty {
      if let bodyString = self.curlBodyString(
        data: data,
        wasRedacted: body.wasRedacted,
        options: options
      ) {
        parts.append("--data-raw \(bodyString.shellQuoted)")
      } else {
        parts.append("--data-binary \("<\(data.count) bytes>".shellQuoted)")
      }
    }

    parts.append(self.url.absoluteString.shellQuoted)
    return parts.joined(separator: options.style.separator)
  }

  public func curlCommand(redactedHeaders: Set<String>) -> String {
    self.curlCommand(redactionPolicy: RedactionPolicy(redactedHeaders: redactedHeaders))
  }

  private func curlBodyString(
    data: Data,
    wasRedacted: Bool,
    options: CURLCommandOptions
  ) -> String? {
    guard !wasRedacted else {
      return String(data: data, encoding: .utf8)
    }

    switch options.bodyFormatting {
    case .original:
      return String(data: data, encoding: .utf8)
    case .prettyPrintedJSON:
      return Self.prettyPrintedJSONString(from: data)
        ?? String(data: data, encoding: .utf8)
    }
  }

  private static func prettyPrintedJSONString(from data: Data) -> String? {
    let trimmed = String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.first == "{" || trimmed.first == "[" else { return nil }

    do {
      let object = try JSONSerialization.jsonObject(with: data)
      let prettyData = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
      )
      return String(decoding: prettyData, as: UTF8.self)
    } catch {
      return nil
    }
  }
}

private extension CURLCommandStyle {
  var separator: String {
    switch self {
    case .multiline:
      " \\\n  "
    case .compact:
      " "
    }
  }
}

private extension String {
  var shellQuoted: String {
    guard !self.isEmpty else { return "''" }
    return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
