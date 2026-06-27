import Foundation
import HTTPTypes

/// Controls how a generated cURL command is formatted.
public enum CURLCommandStyle: Sendable, Equatable {
  /// Formats each argument on its own continued shell line.
  case multiline
  /// Formats the full command on one shell line.
  case compact
}

extension PreparedRequest {
  public func curlCommand(redactionPolicy: RedactionPolicy? = nil) -> String {
    self.curlCommand(redactionPolicy: redactionPolicy, style: .multiline)
  }

  public func curlCommand(style: CURLCommandStyle) -> String {
    self.curlCommand(redactionPolicy: nil, style: style)
  }

  public func curlCommand(redactionPolicy: RedactionPolicy?, style: CURLCommandStyle) -> String {
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
      if let bodyString = String(data: data, encoding: .utf8) {
        parts.append("--data-raw \(bodyString.shellQuoted)")
      } else {
        parts.append("--data-binary \("<\(data.count) bytes>".shellQuoted)")
      }
    }

    parts.append(self.url.absoluteString.shellQuoted)
    return parts.joined(separator: style.separator)
  }

  public func curlCommand(redactedHeaders: Set<String>) -> String {
    self.curlCommand(redactionPolicy: RedactionPolicy(redactedHeaders: redactedHeaders))
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
