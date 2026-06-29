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
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    let encoding = CFStringConvertIANACharSetNameToEncoding(ianaCharsetName as CFString)
    guard encoding != kCFStringEncodingInvalidId else { return nil }
    self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    #else
    switch ianaCharsetName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "-") {
    case "utf-8", "utf8":
      self = .utf8
    case "us-ascii", "ascii":
      self = .ascii
    case "iso-8859-1", "latin1", "latin-1":
      self = .isoLatin1
    case "utf-16", "utf16":
      self = .utf16
    case "utf-16be", "utf16be":
      self = .utf16BigEndian
    case "utf-16le", "utf16le":
      self = .utf16LittleEndian
    case "utf-32", "utf32":
      self = .utf32
    case "utf-32be", "utf32be":
      self = .utf32BigEndian
    case "utf-32le", "utf32le":
      self = .utf32LittleEndian
    default:
      return nil
    }
    #endif
  }
}
