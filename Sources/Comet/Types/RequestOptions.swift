import Foundation

/// Collects opt-in request behavior that would otherwise bloat every ``APIRequest``.
public struct RequestOptions: Sendable {
  /// Prepends a version segment to the request path when your API expects versioned routes.
  public var apiVersion: String?
  /// Replaces the configured base URL and path-building behavior with a fully qualified URL.
  public var absoluteURL: URL?
  /// Overrides the client's default request timeout for this request only.
  public var timeout: Duration?
  /// Provides an idempotency key for APIs that support safe retries.
  public var idempotencyKey: String?
  /// Deduplicates concurrent in-flight requests that share the same key.
  public var deduplicationKey: String?
  /// Carries human-readable request identity into logs, activity, traces, and fixtures.
  public var metadata: RequestMetadata
  /// Controls which HTTP status codes are considered successful.
  public var statusValidation: StatusValidation
  /// Overrides the client's redaction policy for this request.
  public var redactionPolicy: RedactionPolicy?
  /// Controls whether retry middleware may retry this request.
  public var retryPolicy: RequestRetryPolicy?
  /// Adds per-request middleware on top of the client's shared middleware.
  public var middleware: [any Middleware]
  /// Controls how ``CacheMiddleware`` reads and writes cached responses for this request.
  public var cachePolicy: HTTPCachePolicy

  /// Creates a request-specific override bundle with all options disabled by default.
  public init(
    apiVersion: String? = nil,
    absoluteURL: URL? = nil,
    timeout: Duration? = nil,
    idempotencyKey: String? = nil,
    deduplicationKey: String? = nil,
    metadata: RequestMetadata = .none,
    statusValidation: StatusValidation = .successCodes,
    redactionPolicy: RedactionPolicy? = nil,
    retryPolicy: RequestRetryPolicy? = nil,
    middleware: [any Middleware] = []
  ) {
    self.apiVersion = apiVersion
    self.absoluteURL = absoluteURL
    self.timeout = timeout
    self.idempotencyKey = idempotencyKey
    self.deduplicationKey = deduplicationKey
    self.metadata = metadata
    self.statusValidation = statusValidation
    self.redactionPolicy = redactionPolicy
    self.retryPolicy = retryPolicy
    self.middleware = middleware
    self.cachePolicy = .disabled
  }

  /// Creates request-specific overrides including cache behavior.
  public init(
    apiVersion: String? = nil,
    absoluteURL: URL? = nil,
    timeout: Duration? = nil,
    idempotencyKey: String? = nil,
    deduplicationKey: String? = nil,
    metadata: RequestMetadata = .none,
    statusValidation: StatusValidation = .successCodes,
    redactionPolicy: RedactionPolicy? = nil,
    retryPolicy: RequestRetryPolicy? = nil,
    middleware: [any Middleware] = [],
    cachePolicy: HTTPCachePolicy
  ) {
    self.apiVersion = apiVersion
    self.absoluteURL = absoluteURL
    self.timeout = timeout
    self.idempotencyKey = idempotencyKey
    self.deduplicationKey = deduplicationKey
    self.metadata = metadata
    self.statusValidation = statusValidation
    self.redactionPolicy = redactionPolicy
    self.retryPolicy = retryPolicy
    self.middleware = middleware
    self.cachePolicy = cachePolicy
  }
}
