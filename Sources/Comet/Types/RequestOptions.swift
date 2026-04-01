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
  /// Controls which HTTP status codes are considered successful.
  public var statusValidation: StatusValidation
  /// Adds per-request middleware on top of the client's shared middleware.
  public var middleware: [any Middleware]

  /// Creates a request-specific override bundle with all options disabled by default.
  public init(
    apiVersion: String? = nil,
    absoluteURL: URL? = nil,
    timeout: Duration? = nil,
    idempotencyKey: String? = nil,
    deduplicationKey: String? = nil,
    statusValidation: StatusValidation = .successCodes,
    middleware: [any Middleware] = []
  ) {
    self.apiVersion = apiVersion
    self.absoluteURL = absoluteURL
    self.timeout = timeout
    self.idempotencyKey = idempotencyKey
    self.deduplicationKey = deduplicationKey
    self.statusValidation = statusValidation
    self.middleware = middleware
  }
}
