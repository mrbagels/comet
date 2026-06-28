import Foundation

struct MiddlewareChain: Sendable {
  let middleware: [any Middleware]
  let sleep: @Sendable (Duration) async throws -> Void
  let onRetry: @Sendable (UUID, Int, Duration) async -> Void
  let now: @Sendable () -> ContinuousClock.Instant
  let onAttempt: @Sendable (UUID, Int, PreparedRequest, Result<RawResponse, NetworkError>, Duration) async -> Void

  init(
    middleware: [any Middleware],
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    onRetry: @escaping @Sendable (UUID, Int, Duration) async -> Void,
    now: @escaping @Sendable () -> ContinuousClock.Instant,
    onAttempt: @escaping @Sendable (UUID, Int, PreparedRequest, Result<RawResponse, NetworkError>, Duration) async -> Void = { _, _, _, _, _ in }
  ) {
    self.middleware = middleware
    self.sleep = sleep
    self.onRetry = onRetry
    self.now = now
    self.onAttempt = onAttempt
  }

  func execute(
    _ request: PreparedRequest,
    context: MiddlewareContext,
    perform: @escaping @Sendable (PreparedRequest) async throws(NetworkError) -> RawResponse
  ) async throws(NetworkError) -> RawResponse {
    var currentRequest = request
    var currentContext = context

    while true {
      for middleware in self.middleware {
        currentRequest = try await middleware.prepare(currentRequest, context: currentContext)
      }

      let initialResult: Result<RawResponse, NetworkError>
      let attemptStartedAt = self.now()
      do {
        let response = try await perform(currentRequest)
        initialResult = .success(response)
      } catch {
        initialResult = .failure(.from(error))
      }
      let attemptDuration = attemptStartedAt.duration(to: self.now())
      await self.onAttempt(
        currentContext.requestID,
        currentContext.attempt + 1,
        currentRequest,
        initialResult,
        attemptDuration
      )

      var currentResult = initialResult
      var retry: (PreparedRequest, Duration)?

      for middleware in self.middleware {
        let result = try await middleware.process(
          result: currentResult,
          request: currentRequest,
          context: currentContext
        )

        switch result {
        case .proceed(let nextResult):
          currentResult = nextResult
        case .retry(let retryRequest, let delay):
          retry = (retryRequest, delay)
        case .fail(let error):
          currentResult = .failure(error)
        }

        if retry != nil {
          break
        }
      }

      if let (retryRequest, delay) = retry {
        if delay > .zero {
          do {
            try await self.sleep(delay)
          } catch {
            throw NetworkError.from(error)
          }
        }
        await self.onRetry(currentContext.requestID, currentContext.attempt + 1, delay)
        currentRequest = retryRequest
        currentContext = currentContext.nextAttempt()
        continue
      }

      switch currentResult {
      case .success(let response):
        return response
      case .failure(let error):
        throw error
      }
    }
  }
}
