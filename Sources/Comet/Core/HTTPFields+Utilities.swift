import Foundation
import HTTPTypes

extension HTTPFields {
  mutating func merge(_ other: HTTPFields) {
    let names = Set(other.map(\.name))
    for name in names {
      self[fields: name] = other[fields: name]
    }
  }

  init(_ headerFields: [AnyHashable: Any]) {
    self.init()
    for (key, value) in headerFields {
      let name = String(describing: key)
      let stringValue = String(describing: value)
      if let fieldName = HTTPField.Name(name) {
        self[fieldName] = stringValue
      }
    }
  }

  func redactedDescription(redactionPolicy: RedactionPolicy) -> String {
    self
      .map { field in
        let name = field.name.canonicalName
        let value = redactionPolicy.redactedHeaderValue(name: name, value: field.value)
        return "\(name): \(value)"
      }
      .joined(separator: ", ")
  }

  func redactedDescription(redactedHeaders: Set<String>) -> String {
    self.redactedDescription(redactionPolicy: RedactionPolicy(redactedHeaders: redactedHeaders))
  }

  var combinedForFoundation: [String: String] {
    var combined = [HTTPField.Name: String](minimumCapacity: self.count)
    for field in self {
      if let existing = combined[field.name] {
        let separator = field.name == .cookie ? "; " : ", "
        combined[field.name] = "\(existing)\(separator)\(field.value)"
      } else {
        combined[field.name] = field.value
      }
    }

    return combined.reduce(into: [String: String]()) { result, entry in
      result[entry.key.rawName] = entry.value
    }
  }

  var suggestedTextEncoding: String.Encoding? {
    guard let contentType = self[.contentType] else { return nil }

    let charsetParameter = contentType
      .split(separator: ";")
      .dropFirst()
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { $0.lowercased().hasPrefix("charset=") }
      .map { String($0.dropFirst("charset=".count)) }

    let charset = charsetParameter?
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

    guard let charset else { return nil }
    return String.Encoding(ianaCharsetName: charset)
  }
}

extension Duration {
  var timeInterval: Double {
    let components = self.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }
}

extension String.Encoding {
  init?(ianaCharsetName: String) {
    let encoding = CFStringConvertIANACharSetNameToEncoding(ianaCharsetName as CFString)
    guard encoding != kCFStringEncodingInvalidId else { return nil }
    self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
  }
}
