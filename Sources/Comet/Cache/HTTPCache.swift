import Foundation
import HTTPTypes

/// Selects how ``CacheMiddleware`` reads from and writes to an HTTP cache.
public struct HTTPCachePolicy: Sendable, Hashable {
  public enum Strategy: String, Sendable, Hashable {
    case disabled
    case cacheOnly
    case networkOnly
    case returnCacheElseLoad
    case reloadIgnoringCache
    case revalidate
  }

  public var strategy: Strategy
  public var allowsUnsafeMethods: Bool
  public var allowsStaleIfError: Bool
  public var defaultFreshnessLifetime: Duration?
  public var isShared: Bool
  public var respectsVary: Bool

  public init(
    strategy: Strategy = .returnCacheElseLoad,
    allowsUnsafeMethods: Bool = false,
    allowsStaleIfError: Bool = false,
    defaultFreshnessLifetime: Duration? = nil,
    isShared: Bool = false,
    respectsVary: Bool = true
  ) {
    self.strategy = strategy
    self.allowsUnsafeMethods = allowsUnsafeMethods
    self.allowsStaleIfError = allowsStaleIfError
    self.defaultFreshnessLifetime = defaultFreshnessLifetime
    self.isShared = isShared
    self.respectsVary = respectsVary
  }

  public static let disabled = Self(strategy: .disabled)
  public static let cacheOnly = Self(strategy: .cacheOnly)
  public static let networkOnly = Self(strategy: .networkOnly)
  public static let returnCacheElseLoad = Self(strategy: .returnCacheElseLoad)
  public static let reloadIgnoringCache = Self(strategy: .reloadIgnoringCache)
  public static let revalidate = Self(strategy: .revalidate)
}

/// Parsed response cache directives from `Cache-Control`.
public struct HTTPCacheControl: Sendable, Hashable {
  public var maxAgeSeconds: Int?
  public var sharedMaxAgeSeconds: Int?
  public var staleIfErrorSeconds: Int?
  public var noCache: Bool
  public var noStore: Bool
  public var mustRevalidate: Bool
  public var proxyRevalidate: Bool
  public var isPrivate: Bool
  public var isPublic: Bool

  public init(
    maxAgeSeconds: Int? = nil,
    sharedMaxAgeSeconds: Int? = nil,
    staleIfErrorSeconds: Int? = nil,
    noCache: Bool = false,
    noStore: Bool = false,
    mustRevalidate: Bool = false,
    proxyRevalidate: Bool = false,
    isPrivate: Bool = false,
    isPublic: Bool = false
  ) {
    self.maxAgeSeconds = maxAgeSeconds
    self.sharedMaxAgeSeconds = sharedMaxAgeSeconds
    self.staleIfErrorSeconds = staleIfErrorSeconds
    self.noCache = noCache
    self.noStore = noStore
    self.mustRevalidate = mustRevalidate
    self.proxyRevalidate = proxyRevalidate
    self.isPrivate = isPrivate
    self.isPublic = isPublic
  }

  public init(headerValue: String?) {
    self.init()
    guard let headerValue else { return }

    for directive in headerValue.split(separator: ",") {
      let parts = directive.split(separator: "=", maxSplits: 1)
      let name = parts[0]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      let value = parts.count > 1
        ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        : nil

      switch name {
      case "max-age":
        self.maxAgeSeconds = value.flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }
      case "s-maxage":
        self.sharedMaxAgeSeconds = value.flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }
      case "stale-if-error":
        self.staleIfErrorSeconds = value.flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }
      case "no-cache":
        self.noCache = true
      case "no-store":
        self.noStore = true
      case "must-revalidate":
        self.mustRevalidate = true
      case "proxy-revalidate":
        self.proxyRevalidate = true
      case "private":
        self.isPrivate = true
      case "public":
        self.isPublic = true
      default:
        break
      }
    }
  }
}

/// Parsed cache metadata used for freshness and validator decisions.
public struct HTTPCacheMetadata: Sendable, Hashable {
  public var cacheControl: HTTPCacheControl
  public var expires: Date?
  public var ageSeconds: Int?
  public var eTag: String?
  public var lastModified: Date?
  public var storedAt: Date

  public init(
    cacheControl: HTTPCacheControl = .init(),
    expires: Date? = nil,
    ageSeconds: Int? = nil,
    eTag: String? = nil,
    lastModified: Date? = nil,
    storedAt: Date = Date()
  ) {
    self.cacheControl = cacheControl
    self.expires = expires
    self.ageSeconds = ageSeconds
    self.eTag = eTag
    self.lastModified = lastModified
    self.storedAt = storedAt
  }

  public init(headers: HTTPFields, storedAt: Date = Date()) {
    self.init(
      cacheControl: HTTPCacheControl(headerValue: headers[CacheHeaderNames.cacheControl]),
      expires: headers[CacheHeaderNames.expires].flatMap(HTTPDate.parse),
      ageSeconds: headers[CacheHeaderNames.age].flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil },
      eTag: headers[CacheHeaderNames.eTag],
      lastModified: headers[CacheHeaderNames.lastModified].flatMap(HTTPDate.parse),
      storedAt: storedAt
    )
  }

  public var hasExplicitFreshness: Bool {
    self.cacheControl.maxAgeSeconds != nil
      || self.cacheControl.sharedMaxAgeSeconds != nil
      || self.cacheControl.noCache
      || self.cacheControl.noStore
      || self.expires != nil
  }

  public var hasValidator: Bool {
    self.eTag != nil || self.lastModified != nil
  }

  public func isFresh(
    at date: Date = Date(),
    isShared: Bool = false,
    defaultFreshnessLifetime: Duration? = nil
  ) -> Bool {
    guard !self.cacheControl.noStore else { return false }
    guard !self.cacheControl.noCache else { return false }
    guard let lifetime = self.freshnessLifetime(
      isShared: isShared,
      defaultFreshnessLifetime: defaultFreshnessLifetime
    ) else { return false }
    return self.currentAge(at: date) <= lifetime
  }

  public func canServeStaleIfError(
    at date: Date = Date(),
    isShared: Bool = false,
    defaultFreshnessLifetime: Duration? = nil
  ) -> Bool {
    guard !self.cacheControl.noStore else { return false }
    guard !self.cacheControl.noCache else { return false }

    let lifetime = self.freshnessLifetime(
      isShared: isShared,
      defaultFreshnessLifetime: defaultFreshnessLifetime
    ) ?? 0
    if let staleIfErrorSeconds = self.cacheControl.staleIfErrorSeconds {
      return self.currentAge(at: date) <= lifetime + Double(staleIfErrorSeconds)
    }

    if self.cacheControl.mustRevalidate || (isShared && self.cacheControl.proxyRevalidate) {
      return false
    }

    return true
  }

  private func freshnessLifetime(
    isShared: Bool,
    defaultFreshnessLifetime: Duration?
  ) -> TimeInterval? {
    if isShared, let sharedMaxAgeSeconds = self.cacheControl.sharedMaxAgeSeconds {
      return Double(sharedMaxAgeSeconds)
    }
    if let maxAgeSeconds = self.cacheControl.maxAgeSeconds {
      return Double(maxAgeSeconds)
    }
    if let expires {
      return max(0, expires.timeIntervalSince(self.storedAt))
    }
    return defaultFreshnessLifetime?.cacheTimeInterval
  }

  private func currentAge(at date: Date) -> TimeInterval {
    max(0, date.timeIntervalSince(self.storedAt) + Double(self.ageSeconds ?? 0))
  }

  public func conditionalHeaders() -> HTTPFields {
    var headers = HTTPFields()
    if let eTag {
      headers[CacheHeaderNames.ifNoneMatch] = eTag
    }
    if let lastModified {
      headers[CacheHeaderNames.ifModifiedSince] = HTTPDate.format(lastModified)
    }
    return headers
  }
}

/// A stable cache key for a prepared HTTP request.
public struct HTTPCacheKey: Sendable, Hashable, CustomStringConvertible {
  public let method: HTTPMethod
  public let url: String

  public init(method: HTTPMethod, url: URL) {
    self.method = method
    self.url = url.absoluteString
  }

  public init(request: PreparedRequest) {
    self.init(method: request.method, url: request.url)
  }

  public var description: String {
    "\(self.method.rawValue) \(self.url)"
  }
}

/// A cached raw HTTP response plus local cache metadata.
public struct CachedHTTPResponse: Sendable {
  public var data: Data
  public var statusCode: Int
  public var headers: HTTPFields
  public var storedAt: Date
  public var requestVaryHeaderValues: [String: String]

  public init(
    data: Data,
    statusCode: Int,
    headers: HTTPFields = .init(),
    storedAt: Date = Date(),
    requestVaryHeaderValues: [String: String] = [:]
  ) {
    self.data = data
    self.statusCode = statusCode
    self.headers = headers
    self.storedAt = storedAt
    self.requestVaryHeaderValues = requestVaryHeaderValues
  }

  public init(
    response: RawResponse,
    storedAt: Date = Date(),
    requestHeaders: HTTPFields = .init()
  ) {
    self.init(
      data: response.data,
      statusCode: response.statusCode,
      headers: response.headers,
      storedAt: storedAt,
      requestVaryHeaderValues: response.headers.varyRequestHeaderValues(from: requestHeaders)
    )
  }

  public var rawResponse: RawResponse {
    RawResponse(data: self.data, statusCode: self.statusCode, headers: self.headers)
  }

  public var cacheMetadata: HTTPCacheMetadata {
    HTTPCacheMetadata(headers: self.headers, storedAt: self.storedAt)
  }

  public func mergingNotModifiedResponse(
    _ response: RawResponse,
    storedAt: Date = Date()
  ) -> CachedHTTPResponse {
    var headers = self.headers
    headers.merge(response.headers)
    return CachedHTTPResponse(
      data: self.data,
      statusCode: self.statusCode,
      headers: headers,
      storedAt: storedAt,
      requestVaryHeaderValues: self.requestVaryHeaderValues
    )
  }

  public func matchesVaryHeaders(for request: PreparedRequest) -> Bool {
    let names = self.headers.varyHeaderNames
    guard !names.contains("*") else { return false }
    for name in names {
      guard let headerName = HTTPField.Name(name) else { return false }
      let key = name.lowercased()
      guard self.requestVaryHeaderValues[key] == (request.headers[headerName] ?? "") else {
        return false
      }
    }
    return true
  }
}

/// Stores cached HTTP responses behind an async boundary.
public protocol HTTPCacheStore: Sendable {
  func cachedResponse(for key: HTTPCacheKey) async -> CachedHTTPResponse?
  func store(_ response: CachedHTTPResponse, for key: HTTPCacheKey) async
  func removeCachedResponse(for key: HTTPCacheKey) async
  func removeAllCachedResponses() async
}

/// An actor-backed in-memory cache store for tests, previews, and process-local reads.
public actor MemoryHTTPCacheStore: HTTPCacheStore {
  private var responses: [HTTPCacheKey: CachedHTTPResponse]

  public init(responses: [HTTPCacheKey: CachedHTTPResponse] = [:]) {
    self.responses = responses
  }

  public func cachedResponse(for key: HTTPCacheKey) -> CachedHTTPResponse? {
    self.responses[key]
  }

  public func store(_ response: CachedHTTPResponse, for key: HTTPCacheKey) {
    self.responses[key] = response
  }

  public func removeCachedResponse(for key: HTTPCacheKey) {
    self.responses[key] = nil
  }

  public func removeAllCachedResponses() {
    self.responses.removeAll()
  }

  public var count: Int {
    self.responses.count
  }
}

/// A cache decision recorded on a completed ``RequestTrace``.
public struct RequestCacheTraceEvent: Sendable, Hashable {
  public enum Kind: String, Sendable, Hashable {
    case hit
    case miss
    case bypass
    case stale
    case revalidate
    case update
    case store
    case skippedStore
  }

  public enum Reason: String, Sendable, Hashable {
    case policyDisabled
    case unsafeMethod
    case cacheOnlyMiss
    case networkOnly
    case reloadIgnoringCache
    case statusNotCacheable
    case noStore
    case noValidator
    case noExplicitFreshness
    case stale
    case fresh
    case notModified
    case replaced
    case cacheHit
    case staleIfError
    case varyMismatch
    case varyWildcard
    case privateResponse
    case mustRevalidate
  }

  public let kind: Kind
  public let key: HTTPCacheKey
  public let policy: HTTPCachePolicy
  public let reason: Reason?

  public init(
    kind: Kind,
    key: HTTPCacheKey,
    policy: HTTPCachePolicy,
    reason: Reason? = nil
  ) {
    self.kind = kind
    self.key = key
    self.policy = policy
    self.reason = reason
  }
}

/// Adds conservative opt-in HTTP caching to an ``HTTPClient`` middleware chain.
public struct CacheMiddleware: ResponseProvidingMiddleware {
  private let store: any HTTPCacheStore
  private let now: @Sendable () -> Date
  private let state = CacheMiddlewareState()

  public init(
    store: some HTTPCacheStore,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.store = store
    self.now = now
  }

  public func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest {
    let policy = context.cachePolicy
    let key = HTTPCacheKey(request: request)

    guard policy.strategy.shouldReadCache else { return request }
    guard policy.strategy != .cacheOnly else { return request }
    guard policy.allowsUnsafeMethods || request.method.isAutomaticallyCacheable else { return request }
    guard let cached = await self.store.cachedResponse(for: key) else { return request }

    let metadata = cached.cacheMetadata
    if metadata.cacheControl.noStore {
      await self.store.removeCachedResponse(for: key)
      await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .noStore))
      return request
    }
    if policy.isShared && metadata.cacheControl.isPrivate {
      await self.store.removeCachedResponse(for: key)
      await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .privateResponse))
      return request
    }
    guard await self.cachedResponseMatchesVary(cached, request: request, context: context, policy: policy, key: key) else {
      return request
    }

    let isFresh = metadata.isFresh(
      at: self.now(),
      isShared: policy.isShared,
      defaultFreshnessLifetime: policy.defaultFreshnessLifetime
    )
    guard policy.strategy == .revalidate || !isFresh else {
      return request
    }

    await self.state.markCached(requestID: context.requestID, cached: cached)
    if !isFresh {
      await context.recordCacheEvent(.init(kind: .stale, key: key, policy: policy, reason: .stale))
    }

    let conditionalHeaders = metadata.conditionalHeaders()
    guard !conditionalHeaders.isEmpty else {
      await context.recordCacheEvent(.init(kind: .revalidate, key: key, policy: policy, reason: .noValidator))
      return request
    }

    var headers = request.headers
    headers.merge(conditionalHeaders)
    await context.recordCacheEvent(.init(kind: .revalidate, key: key, policy: policy))
    return PreparedRequest(
      url: request.url,
      method: request.method,
      headers: headers,
      body: request.body,
      timeout: request.timeout,
      metadata: request.metadata,
      redactionPolicy: request.redactionPolicy,
      retryPolicy: request.retryPolicy
    )
  }

  public func respond(
    to request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> RawResponse? {
    let policy = context.cachePolicy
    let key = HTTPCacheKey(request: request)

    guard policy.strategy != .disabled else {
      await context.recordCacheEvent(.init(kind: .bypass, key: key, policy: policy, reason: .policyDisabled))
      return nil
    }
    guard policy.strategy != .networkOnly else {
      await context.recordCacheEvent(.init(kind: .bypass, key: key, policy: policy, reason: .networkOnly))
      return nil
    }
    guard policy.allowsUnsafeMethods || request.method.isAutomaticallyCacheable else {
      await context.recordCacheEvent(.init(kind: .bypass, key: key, policy: policy, reason: .unsafeMethod))
      return nil
    }
    guard policy.strategy != .reloadIgnoringCache else {
      await context.recordCacheEvent(.init(kind: .bypass, key: key, policy: policy, reason: .reloadIgnoringCache))
      return nil
    }
    if await self.state.hasCachedResponse(requestID: context.requestID) {
      return nil
    }

    if let cached = await self.store.cachedResponse(for: key) {
      let metadata = cached.cacheMetadata
      if metadata.cacheControl.noStore {
        await self.store.removeCachedResponse(for: key)
        await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .noStore))
        guard policy.strategy != .cacheOnly else {
          throw .middleware("Cached response for \(key) is marked no-store.")
        }
        return nil
      }
      if policy.isShared && metadata.cacheControl.isPrivate {
        await self.store.removeCachedResponse(for: key)
        await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .privateResponse))
        guard policy.strategy != .cacheOnly else {
          throw .middleware("Cached response for \(key) is marked private for a shared cache.")
        }
        return nil
      }
      guard await self.cachedResponseMatchesVary(cached, request: request, context: context, policy: policy, key: key) else {
        guard policy.strategy != .cacheOnly else {
          throw .middleware("Cached response for \(key) does not match the request Vary headers.")
        }
        return nil
      }
      if metadata.cacheControl.noCache && policy.strategy == .cacheOnly {
        await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .stale))
        throw .middleware("Cached response for \(key) requires revalidation.")
      }
      let isFresh = metadata.isFresh(
        at: self.now(),
        isShared: policy.isShared,
        defaultFreshnessLifetime: policy.defaultFreshnessLifetime
      )
      if policy.strategy == .cacheOnly && !isFresh {
        await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .stale))
        throw .middleware("Cached response for \(key) is stale.")
      }
      if policy.strategy != .cacheOnly && !isFresh {
        await self.state.markCached(requestID: context.requestID, cached: cached)
        await context.recordCacheEvent(.init(kind: .stale, key: key, policy: policy, reason: .stale))
        return nil
      }
      await self.state.markHit(requestID: context.requestID)
      let reason: RequestCacheTraceEvent.Reason = policy.strategy == .cacheOnly ? .cacheHit : .fresh
      await context.recordCacheEvent(.init(kind: .hit, key: key, policy: policy, reason: reason))
      return cached.rawResponse
    }

    guard policy.strategy != .cacheOnly else {
      await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .cacheOnlyMiss))
      throw .middleware("No cached response for \(key).")
    }

    await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy))
    return nil
  }

  public func process(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareResult {
    let policy = context.cachePolicy
    let key = HTTPCacheKey(request: request)
    let requestState = await self.state.consume(requestID: context.requestID)

    guard requestState?.servedFromCache != true else {
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .cacheHit))
      return .proceed(result)
    }
    guard policy.strategy != .disabled else {
      return .proceed(result)
    }
    guard policy.strategy != .networkOnly else {
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .networkOnly))
      return .proceed(result)
    }
    guard policy.allowsUnsafeMethods || request.method.isAutomaticallyCacheable else {
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .unsafeMethod))
      return .proceed(result)
    }
    guard case .success(let response) = result else {
      if policy.allowsStaleIfError, let cached = requestState?.cachedResponse {
        let metadata = cached.cacheMetadata
        if metadata.canServeStaleIfError(
          at: self.now(),
          isShared: policy.isShared,
          defaultFreshnessLifetime: policy.defaultFreshnessLifetime
        ) {
          await context.recordCacheEvent(.init(kind: .hit, key: key, policy: policy, reason: .staleIfError))
          return .proceed(.success(cached.rawResponse))
        }
        if metadata.cacheControl.mustRevalidate || (policy.isShared && metadata.cacheControl.proxyRevalidate) {
          await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .mustRevalidate))
        }
      }
      return .proceed(result)
    }
    if response.statusCode == 304, let cached = requestState?.cachedResponse {
      let merged = cached.mergingNotModifiedResponse(response, storedAt: self.now())
      await self.store.store(merged, for: key)
      await context.recordCacheEvent(.init(kind: .update, key: key, policy: policy, reason: .notModified))
      return .proceed(.success(merged.rawResponse))
    }
    guard (200..<300).contains(response.statusCode) else {
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .statusNotCacheable))
      return .proceed(result)
    }
    let metadata = HTTPCacheMetadata(headers: response.headers, storedAt: self.now())
    guard !metadata.cacheControl.noStore else {
      await self.store.removeCachedResponse(for: key)
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .noStore))
      return .proceed(result)
    }
    guard !(policy.isShared && metadata.cacheControl.isPrivate) else {
      await self.store.removeCachedResponse(for: key)
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .privateResponse))
      return .proceed(result)
    }
    guard !response.headers.varyHeaderNames.contains("*") else {
      await self.store.removeCachedResponse(for: key)
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .varyWildcard))
      return .proceed(result)
    }
    guard metadata.hasExplicitFreshness || metadata.hasValidator || policy.defaultFreshnessLifetime != nil else {
      await self.store.removeCachedResponse(for: key)
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .noExplicitFreshness))
      return .proceed(result)
    }

    await self.store.store(
      CachedHTTPResponse(
        response: response,
        storedAt: metadata.storedAt,
        requestHeaders: request.headers
      ),
      for: key
    )
    let reason: RequestCacheTraceEvent.Reason? = requestState?.cachedResponse == nil ? nil : .replaced
    await context.recordCacheEvent(.init(kind: .store, key: key, policy: policy, reason: reason))
    return .proceed(result)
  }

  public func finish(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async {
    await self.state.discard(requestID: context.requestID)
  }

  private func cachedResponseMatchesVary(
    _ cached: CachedHTTPResponse,
    request: PreparedRequest,
    context: MiddlewareContext,
    policy: HTTPCachePolicy,
    key: HTTPCacheKey
  ) async -> Bool {
    guard policy.respectsVary else { return true }
    guard !cached.headers.varyHeaderNames.contains("*") else {
      await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .varyWildcard))
      return false
    }
    guard cached.matchesVaryHeaders(for: request) else {
      await context.recordCacheEvent(.init(kind: .miss, key: key, policy: policy, reason: .varyMismatch))
      return false
    }
    return true
  }
}

private struct CacheRequestState: Sendable {
  var cachedResponse: CachedHTTPResponse?
  var servedFromCache = false
}

private actor CacheMiddlewareState {
  private var states: [UUID: CacheRequestState] = [:]

  func markCached(requestID: UUID, cached: CachedHTTPResponse) {
    var state = self.states[requestID, default: CacheRequestState()]
    state.cachedResponse = cached
    self.states[requestID] = state
  }

  func markHit(requestID: UUID) {
    var state = self.states[requestID, default: CacheRequestState()]
    state.servedFromCache = true
    self.states[requestID] = state
  }

  func hasCachedResponse(requestID: UUID) -> Bool {
    self.states[requestID]?.cachedResponse != nil
  }

  func consume(requestID: UUID) -> CacheRequestState? {
    self.states.removeValue(forKey: requestID)
  }

  func discard(requestID: UUID) {
    self.states.removeValue(forKey: requestID)
  }
}

private extension HTTPCachePolicy.Strategy {
  var shouldReadCache: Bool {
    switch self {
    case .cacheOnly, .returnCacheElseLoad, .revalidate:
      true
    case .disabled, .networkOnly, .reloadIgnoringCache:
      false
    }
  }
}

private extension HTTPMethod {
  var isAutomaticallyCacheable: Bool {
    self == .get || self == .head
  }
}

private enum CacheHeaderNames {
  static let age = HTTPField.Name("Age")!
  static let cacheControl = HTTPField.Name("Cache-Control")!
  static let expires = HTTPField.Name("Expires")!
  static let eTag = HTTPField.Name("ETag")!
  static let lastModified = HTTPField.Name("Last-Modified")!
  static let ifNoneMatch = HTTPField.Name("If-None-Match")!
  static let ifModifiedSince = HTTPField.Name("If-Modified-Since")!
  static let vary = HTTPField.Name("Vary")!
}

private extension Duration {
  var cacheTimeInterval: TimeInterval {
    let components = self.components
    return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
  }
}

private extension HTTPFields {
  var varyHeaderNames: [String] {
    guard let value = self[CacheHeaderNames.vary] else { return [] }
    return value
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  func varyRequestHeaderValues(from requestHeaders: HTTPFields) -> [String: String] {
    var values: [String: String] = [:]
    for name in self.varyHeaderNames where name != "*" {
      guard let headerName = HTTPField.Name(name) else { continue }
      values[name.lowercased()] = requestHeaders[headerName] ?? ""
    }
    return values
  }
}

private enum HTTPDate {
  static func parse(_ value: String) -> Date? {
    for format in [
      "EEE, dd MMM yyyy HH:mm:ss zzz",
      "EEEE, dd-MMM-yy HH:mm:ss zzz",
      "EEE MMM d HH:mm:ss yyyy"
    ] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = format
      if let date = formatter.date(from: value) {
        return date
      }
    }
    return nil
  }

  static func format(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return formatter.string(from: date)
  }
}
