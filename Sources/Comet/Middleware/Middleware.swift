import Foundation

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
}

public extension Middleware {
  func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest {
    request
  }

  func process(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareResult {
    .proceed(result)
  }
}

public enum MiddlewareResult: Sendable {
  case proceed(Result<RawResponse, NetworkError>)
  case retry(PreparedRequest, after: Duration = .zero)
  case fail(NetworkError)
}

public struct MiddlewareContext: Sendable {
  public let requestID: UUID
  public let attempt: Int
  public let startTime: ContinuousClock.Instant
  public let randomDouble: @Sendable (ClosedRange<Double>) -> Double

  public init(
    requestID: UUID,
    attempt: Int,
    startTime: ContinuousClock.Instant,
    randomDouble: @escaping @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
  ) {
    self.requestID = requestID
    self.attempt = attempt
    self.startTime = startTime
    self.randomDouble = randomDouble
  }

  func nextAttempt() -> Self {
    Self(
      requestID: self.requestID,
      attempt: self.attempt + 1,
      startTime: self.startTime,
      randomDouble: self.randomDouble
    )
  }
}
