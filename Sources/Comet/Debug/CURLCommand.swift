import Foundation
import HTTPTypes

extension PreparedRequest {
  public func curlCommand(redactedHeaders: Set<String> = ["authorization", "cookie", "set-cookie"]) -> String {
    var parts = ["curl"]
    parts += ["-X", self.method.rawValue]
    for field in self.headers {
      let name = field.name.canonicalName
      let isRedacted = redactedHeaders.contains(name.lowercased())
      let value = isRedacted ? "<redacted>" : field.value
      parts += ["-H", "\"\(name): \(value)\""]
    }
    if let body = self.body, let bodyString = String(data: body, encoding: .utf8), !bodyString.isEmpty {
      parts += ["--data", "'\(bodyString)'"]
    }
    parts += ["\"\(self.url.absoluteString)\""]
    return parts.joined(separator: " \\\n  ")
  }
}
