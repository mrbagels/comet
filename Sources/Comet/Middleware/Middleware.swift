import Foundation

/// Intercepts requests before transport execution and results after transport execution.
public protocol Middleware: Sendable {
  func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest

  func process(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareResult

  func finish(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async
}

/// A middleware capability that can satisfy a request before transport execution.
public protocol ResponseProvidingMiddleware: Middleware {
  func respond(
    to request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> RawResponse?
}

/// A response-providing middleware capability that can refresh a cached response after serving it.
public protocol BackgroundRefreshingMiddleware: ResponseProvidingMiddleware {
  func backgroundRefreshRequest(
    for request: PreparedRequest,
    context: MiddlewareContext,
    refreshContext: MiddlewareContext
  ) async -> PreparedRequest?
}

public extension Middleware {
  /// Returns the request unchanged before transport execution.
  func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest {
    request
  }

  /// Passes the result through unchanged after transport execution.
  func process(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareResult {
    .proceed(result)
  }

  /// Observes terminal request completion after retries and middleware processing have settled.
  func finish(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async {}
}

/// Describes how middleware wants request execution to continue.
public enum MiddlewareResult: Sendable {
  case proceed(Result<RawResponse, NetworkError>)
  case retry(PreparedRequest, after: Duration = .zero)
  case fail(NetworkError)
}

/// Carries per-request execution state into middleware hooks.
public struct MiddlewareContext: Sendable {
  public let requestID: UUID
  public let attempt: Int
  public let startTime: ContinuousClock.Instant
  public let cachePolicy: HTTPCachePolicy
  public let randomDouble: @Sendable (ClosedRange<Double>) -> Double
  public let recordCacheEvent: @Sendable (RequestCacheTraceEvent) async -> Void

  public init(
    requestID: UUID,
    attempt: Int,
    startTime: ContinuousClock.Instant,
    randomDouble: @escaping @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
  ) {
    self.requestID = requestID
    self.attempt = attempt
    self.startTime = startTime
    self.cachePolicy = .disabled
    self.randomDouble = randomDouble
    self.recordCacheEvent = { _ in }
  }

  public init(
    requestID: UUID,
    attempt: Int,
    startTime: ContinuousClock.Instant,
    cachePolicy: HTTPCachePolicy,
    randomDouble: @escaping @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) },
    recordCacheEvent: @escaping @Sendable (RequestCacheTraceEvent) async -> Void = { _ in }
  ) {
    self.requestID = requestID
    self.attempt = attempt
    self.startTime = startTime
    self.cachePolicy = cachePolicy
    self.randomDouble = randomDouble
    self.recordCacheEvent = recordCacheEvent
  }

  func nextAttempt() -> Self {
    Self(
      requestID: self.requestID,
      attempt: self.attempt + 1,
      startTime: self.startTime,
      cachePolicy: self.cachePolicy,
      randomDouble: self.randomDouble,
      recordCacheEvent: self.recordCacheEvent
    )
  }

  func backgroundRefresh(
    requestID: UUID,
    startTime: ContinuousClock.Instant,
    recordCacheEvent: @escaping @Sendable (RequestCacheTraceEvent) async -> Void = { _ in }
  ) -> Self {
    Self(
      requestID: requestID,
      attempt: 0,
      startTime: startTime,
      cachePolicy: self.cachePolicy,
      randomDouble: self.randomDouble,
      recordCacheEvent: recordCacheEvent
    )
  }
}
