import Foundation

struct MiddlewareChain: Sendable {
  let middleware: [any Middleware]
  let sleep: @Sendable (Duration) async throws -> Void
  let onRetry: @Sendable (UUID, Int, Duration) async -> Void

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
      do {
        initialResult = .success(try await perform(currentRequest))
      } catch {
        initialResult = .failure(.from(error))
      }

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
