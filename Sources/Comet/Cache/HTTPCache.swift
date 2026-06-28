import Foundation
import HTTPTypes

/// Selects how ``CacheMiddleware`` reads from and writes to an HTTP cache.
public struct HTTPCachePolicy: Sendable, Hashable {
  public enum Strategy: String, Sendable, Hashable {
    case disabled
    case returnCacheElseLoad
    case reloadIgnoringCache
  }

  public var strategy: Strategy
  public var allowsUnsafeMethods: Bool

  public init(
    strategy: Strategy = .returnCacheElseLoad,
    allowsUnsafeMethods: Bool = false
  ) {
    self.strategy = strategy
    self.allowsUnsafeMethods = allowsUnsafeMethods
  }

  public static let disabled = Self(strategy: .disabled)
  public static let returnCacheElseLoad = Self(strategy: .returnCacheElseLoad)
  public static let reloadIgnoringCache = Self(strategy: .reloadIgnoringCache)
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

  public init(
    data: Data,
    statusCode: Int,
    headers: HTTPFields = .init(),
    storedAt: Date = Date()
  ) {
    self.data = data
    self.statusCode = statusCode
    self.headers = headers
    self.storedAt = storedAt
  }

  public init(response: RawResponse, storedAt: Date = Date()) {
    self.init(
      data: response.data,
      statusCode: response.statusCode,
      headers: response.headers,
      storedAt: storedAt
    )
  }

  public var rawResponse: RawResponse {
    RawResponse(data: self.data, statusCode: self.statusCode, headers: self.headers)
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
    case store
    case skippedStore
  }

  public enum Reason: String, Sendable, Hashable {
    case policyDisabled
    case unsafeMethod
    case reloadIgnoringCache
    case statusNotCacheable
    case cacheHit
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
  private let state = CacheMiddlewareState()

  public init(store: some HTTPCacheStore) {
    self.store = store
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
    guard policy.allowsUnsafeMethods || request.method.isAutomaticallyCacheable else {
      await context.recordCacheEvent(.init(kind: .bypass, key: key, policy: policy, reason: .unsafeMethod))
      return nil
    }
    guard policy.strategy != .reloadIgnoringCache else {
      await context.recordCacheEvent(.init(kind: .bypass, key: key, policy: policy, reason: .reloadIgnoringCache))
      return nil
    }

    if let cached = await self.store.cachedResponse(for: key) {
      await self.state.markHit(requestID: context.requestID)
      await context.recordCacheEvent(.init(kind: .hit, key: key, policy: policy))
      return cached.rawResponse
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

    let servedFromCache = await self.state.consumeHit(requestID: context.requestID)
    guard !servedFromCache else {
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .cacheHit))
      return .proceed(result)
    }
    guard policy.strategy != .disabled else {
      return .proceed(result)
    }
    guard policy.allowsUnsafeMethods || request.method.isAutomaticallyCacheable else {
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .unsafeMethod))
      return .proceed(result)
    }
    guard case .success(let response) = result else {
      return .proceed(result)
    }
    guard (200..<300).contains(response.statusCode) else {
      await context.recordCacheEvent(.init(kind: .skippedStore, key: key, policy: policy, reason: .statusNotCacheable))
      return .proceed(result)
    }

    await self.store.store(CachedHTTPResponse(response: response), for: key)
    await context.recordCacheEvent(.init(kind: .store, key: key, policy: policy))
    return .proceed(result)
  }
}

private actor CacheMiddlewareState {
  private var hitRequestIDs: Set<UUID> = []

  func markHit(requestID: UUID) {
    self.hitRequestIDs.insert(requestID)
  }

  func consumeHit(requestID: UUID) -> Bool {
    self.hitRequestIDs.remove(requestID) != nil
  }
}

private extension HTTPMethod {
  var isAutomaticallyCacheable: Bool {
    self == .get || self == .head
  }
}
