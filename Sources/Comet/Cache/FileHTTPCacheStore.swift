import CryptoKit
import Foundation
import HTTPTypes

/// Configuration for ``FileHTTPCacheStore``.
public struct FileHTTPCacheStoreConfiguration: Sendable, Hashable {
  public var directoryURL: URL
  public var namespace: String
  public var maximumSizeBytes: Int
  public var maximumEntrySizeBytes: Int?

  public init(
    directoryURL: URL = Self.defaultDirectoryURL(),
    namespace: String = "default",
    maximumSizeBytes: Int = 50 * 1024 * 1024,
    maximumEntrySizeBytes: Int? = nil
  ) {
    self.directoryURL = directoryURL
    self.namespace = namespace
    self.maximumSizeBytes = max(0, maximumSizeBytes)
    self.maximumEntrySizeBytes = maximumEntrySizeBytes.map { max(0, $0) }
  }

  public var resolvedDirectoryURL: URL {
    self.directoryURL.appendingPathComponent(Self.sanitizedNamespace(self.namespace), isDirectory: true)
  }

  public static func defaultDirectoryURL() -> URL {
    let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return cachesURL.appendingPathComponent("Comet/HTTPCache", isDirectory: true)
  }

  private static func sanitizedNamespace(_ namespace: String) -> String {
    let trimmed = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "default" }

    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let sanitized = String(
      trimmed.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "-"
      }
    )
    guard sanitized != "." && sanitized != ".." else { return "default" }
    return sanitized
  }
}

/// A file-backed HTTP cache store with namespace isolation and size pruning.
public actor FileHTTPCacheStore: HTTPCacheStore {
  public let configuration: FileHTTPCacheStoreConfiguration

  public init(configuration: FileHTTPCacheStoreConfiguration = .init()) {
    self.configuration = configuration
  }

  public init(
    directoryURL: URL = FileHTTPCacheStoreConfiguration.defaultDirectoryURL(),
    namespace: String = "default",
    maximumSizeBytes: Int = 50 * 1024 * 1024,
    maximumEntrySizeBytes: Int? = nil
  ) {
    self.configuration = FileHTTPCacheStoreConfiguration(
      directoryURL: directoryURL,
      namespace: namespace,
      maximumSizeBytes: maximumSizeBytes,
      maximumEntrySizeBytes: maximumEntrySizeBytes
    )
  }

  public func cachedResponse(for key: HTTPCacheKey) -> CachedHTTPResponse? {
    let url = self.fileURL(for: key)
    do {
      let data = try Data(contentsOf: url)
      let entry = try FileCachedHTTPResponse.jsonDecoder().decode(FileCachedHTTPResponse.self, from: data)
      guard entry.matches(key) else {
        try? FileManager.default.removeItem(at: url)
        return nil
      }
      return try entry.cachedResponse()
    } catch {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
  }

  public func store(_ response: CachedHTTPResponse, for key: HTTPCacheKey) {
    do {
      try self.ensureDirectoryExists()
      let entry = FileCachedHTTPResponse(key: key, response: response)
      let data = try entry.encoded()

      if let maximumEntrySizeBytes = self.configuration.maximumEntrySizeBytes,
         data.count > maximumEntrySizeBytes {
        try? FileManager.default.removeItem(at: self.fileURL(for: key))
        return
      }

      try data.write(to: self.fileURL(for: key), options: .atomic)
      self.pruneIfNeeded()
    } catch {
      return
    }
  }

  public func removeCachedResponse(for key: HTTPCacheKey) {
    try? FileManager.default.removeItem(at: self.fileURL(for: key))
  }

  public func removeAllCachedResponses() {
    try? FileManager.default.removeItem(at: self.configuration.resolvedDirectoryURL)
  }

  /// Returns the number of cache entry files in the configured namespace.
  public func count() -> Int {
    self.entryFiles().count
  }

  /// Returns the current on-disk size of cache entry files in bytes.
  public func currentSizeBytes() -> Int {
    self.entryFiles().reduce(0) { partial, file in
      partial + file.sizeBytes
    }
  }

  /// Prunes the namespace until it fits the configured maximum size.
  public func prune() {
    self.pruneIfNeeded()
  }

  private func ensureDirectoryExists() throws {
    try FileManager.default.createDirectory(
      at: self.configuration.resolvedDirectoryURL,
      withIntermediateDirectories: true
    )
  }

  private func fileURL(for key: HTTPCacheKey) -> URL {
    self.configuration.resolvedDirectoryURL
      .appendingPathComponent(FileHTTPCacheStore.fileName(for: key), isDirectory: false)
  }

  private static func fileName(for key: HTTPCacheKey) -> String {
    let identity = "\(key.method.rawValue)\n\(key.url)"
    let digest = SHA256.hash(data: Data(identity.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(key.method.rawValue)-\(hex).json"
  }

  private func pruneIfNeeded() {
    var files = self.entryFiles()
    var totalSize = files.reduce(0) { partial, file in partial + file.sizeBytes }
    guard totalSize > self.configuration.maximumSizeBytes else { return }

    files.sort { lhs, rhs in
      if lhs.storedAt == rhs.storedAt {
        return lhs.url.lastPathComponent < rhs.url.lastPathComponent
      }
      return lhs.storedAt < rhs.storedAt
    }

    for file in files where totalSize > self.configuration.maximumSizeBytes {
      try? FileManager.default.removeItem(at: file.url)
      totalSize -= file.sizeBytes
    }
  }

  private func entryFiles() -> [FileCacheEntryMetadata] {
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: self.configuration.resolvedDirectoryURL,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return urls.compactMap { url in
      guard url.pathExtension == "json" else { return nil }
      guard let data = try? Data(contentsOf: url) else { return nil }
      guard let entry = try? FileCachedHTTPResponse.jsonDecoder().decode(FileCachedHTTPResponse.self, from: data) else {
        try? FileManager.default.removeItem(at: url)
        return nil
      }
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count
      return FileCacheEntryMetadata(url: url, sizeBytes: size, storedAt: entry.storedAt)
    }
  }
}

private struct FileCacheEntryMetadata: Sendable {
  var url: URL
  var sizeBytes: Int
  var storedAt: Date
}

private struct FileCachedHTTPResponse: Codable {
  var method: String
  var url: String
  var statusCode: Int
  var headers: [FileCachedHeader]
  var bodyBase64: String
  var storedAt: Date

  init(key: HTTPCacheKey, response: CachedHTTPResponse) {
    self.method = key.method.rawValue
    self.url = key.url
    self.statusCode = response.statusCode
    self.headers = response.headers.fileCachedHeaders
    self.bodyBase64 = response.data.base64EncodedString()
    self.storedAt = response.storedAt
  }

  func matches(_ key: HTTPCacheKey) -> Bool {
    self.method == key.method.rawValue && self.url == key.url
  }

  func cachedResponse() throws -> CachedHTTPResponse {
    guard let data = Data(base64Encoded: self.bodyBase64) else {
      throw CocoaError(.coderReadCorrupt)
    }
    return CachedHTTPResponse(
      data: data,
      statusCode: self.statusCode,
      headers: try HTTPFields(fileCachedHeaders: self.headers),
      storedAt: self.storedAt
    )
  }

  func encoded() throws -> Data {
    try Self.jsonEncoder().encode(self)
  }

  static func jsonEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  static func jsonDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

private struct FileCachedHeader: Codable {
  var name: String
  var value: String
}

private extension HTTPFields {
  init(fileCachedHeaders: [FileCachedHeader]) throws {
    self.init()
    for header in fileCachedHeaders {
      guard let name = HTTPField.Name(header.name) else {
        throw CocoaError(.coderReadCorrupt)
      }
      self.append(HTTPField(name: name, value: header.value))
    }
  }

  var fileCachedHeaders: [FileCachedHeader] {
    self.map { field in
      FileCachedHeader(name: field.name.rawName, value: field.value)
    }
  }
}
