import Foundation

public struct RetryMiddleware: Middleware {
  public var maxAttempts: Int
  public var backoff: BackoffStrategy
  public var jitter: Double
  public var retryableStatusCodes: Set<Int>

  public init(
    maxAttempts: Int = 3,
    backoff: BackoffStrategy = .exponential(base: .seconds(0.5), multiplier: 2, max: .seconds(8)),
    jitter: Double = 0.1,
    retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]
  ) {
    self.maxAttempts = maxAttempts
    self.backoff = backoff
    self.jitter = jitter
    self.retryableStatusCodes = retryableStatusCodes
  }

  public func process(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareResult {
    guard context.attempt + 1 < self.maxAttempts else {
      return .proceed(result)
    }

    let shouldRetry: Bool
    switch result {
    case .success(let response):
      shouldRetry = self.retryableStatusCodes.contains(response.statusCode)
    case .failure(let error):
      shouldRetry = self.isRetryable(error: error)
    }

    guard shouldRetry else {
      return .proceed(result)
    }

    return .retry(
      request,
      after: self.backoff.delay(
        for: context.attempt + 1,
        jitter: self.jitter,
        randomDouble: context.randomDouble
      )
    )
  }

  private func isRetryable(error: NetworkError) -> Bool {
    switch error {
    case .transport(let urlError):
      return [
        URLError.notConnectedToInternet,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .timedOut
      ].contains(urlError.code)
    case .timeout:
      return true
    default:
      return false
    }
  }
}

public enum BackoffStrategy: Sendable {
  case constant(Duration)
  case linear(Duration)
  case exponential(base: Duration, multiplier: Double, max: Duration)

  func delay(
    for attempt: Int,
    jitter: Double,
    randomDouble: @Sendable (ClosedRange<Double>) -> Double
  ) -> Duration {
    let baseSeconds: Double
    switch self {
    case .constant(let duration):
      baseSeconds = duration.timeInterval
    case .linear(let step):
      baseSeconds = step.timeInterval * Double(attempt)
    case .exponential(let base, let multiplier, let maxDelay):
      let delay = base.timeInterval * pow(multiplier, Double(Swift.max(0, attempt - 1)))
      baseSeconds = min(delay, maxDelay.timeInterval)
    }

    guard baseSeconds > 0 else { return .zero }

    let clampedJitter = Swift.max(0, jitter)
    let factor: Double
    if clampedJitter == 0 {
      factor = 1
    } else {
      factor = randomDouble(Swift.max(0, 1 - clampedJitter)...(1 + clampedJitter))
    }

    return .milliseconds(Int64((Swift.max(0, baseSeconds * factor) * 1000).rounded(.up)))
  }
}
