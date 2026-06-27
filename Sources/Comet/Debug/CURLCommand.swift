import Foundation
import HTTPTypes

extension PreparedRequest {
  public func curlCommand(redactionPolicy: RedactionPolicy? = nil) -> String {
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
    return parts.joined(separator: " \\\n  ")
  }

  public func curlCommand(redactedHeaders: Set<String>) -> String {
    self.curlCommand(redactionPolicy: RedactionPolicy(redactedHeaders: redactedHeaders))
  }
}

private extension String {
  var shellQuoted: String {
    guard !self.isEmpty else { return "''" }
    return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
