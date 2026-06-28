import Foundation

struct MiddlewareChain: Sendable {
  private struct MiddlewareProvidedResponse: Sendable {
    var response: RawResponse
    var provider: (any ResponseProvidingMiddleware)?
  }

  let middleware: [any Middleware]
  let sleep: @Sendable (Duration) async throws -> Void
  let makeRequestID: @Sendable () -> UUID
  let onRetry: @Sendable (UUID, Int, Duration, PreparedRequest) async -> Void
  let now: @Sendable () -> ContinuousClock.Instant
  let onAttempt: @Sendable (UUID, Int, PreparedRequest, Result<RawResponse, NetworkError>, Duration) async -> Void
  let onBackgroundRefreshStarted: @Sendable (UUID, PreparedRequest) async -> Void
  let onBackgroundRefreshCompleted: @Sendable (UUID, PreparedRequest, Result<RawResponse, NetworkError>, Duration) async -> Void
  let onBackgroundCacheEvent: @Sendable (UUID, RequestCacheTraceEvent) async -> Void

  init(
    middleware: [any Middleware],
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    makeRequestID: @escaping @Sendable () -> UUID = UUID.init,
    onRetry: @escaping @Sendable (UUID, Int, Duration, PreparedRequest) async -> Void,
    now: @escaping @Sendable () -> ContinuousClock.Instant,
    onAttempt: @escaping @Sendable (UUID, Int, PreparedRequest, Result<RawResponse, NetworkError>, Duration) async -> Void = { _, _, _, _, _ in },
    onBackgroundRefreshStarted: @escaping @Sendable (UUID, PreparedRequest) async -> Void = { _, _ in },
    onBackgroundRefreshCompleted: @escaping @Sendable (UUID, PreparedRequest, Result<RawResponse, NetworkError>, Duration) async -> Void = { _, _, _, _ in },
    onBackgroundCacheEvent: @escaping @Sendable (UUID, RequestCacheTraceEvent) async -> Void = { _, _ in }
  ) {
    self.middleware = middleware
    self.sleep = sleep
    self.makeRequestID = makeRequestID
    self.onRetry = onRetry
    self.now = now
    self.onAttempt = onAttempt
    self.onBackgroundRefreshStarted = onBackgroundRefreshStarted
    self.onBackgroundRefreshCompleted = onBackgroundRefreshCompleted
    self.onBackgroundCacheEvent = onBackgroundCacheEvent
  }

  func execute(
    _ request: PreparedRequest,
    context: MiddlewareContext,
    perform: @escaping @Sendable (PreparedRequest) async throws(NetworkError) -> RawResponse
  ) async throws(NetworkError) -> RawResponse {
    var currentRequest = request
    var currentContext = context
    var didFinish = false

    do {
      while true {
        for middleware in self.middleware {
          currentRequest = try await middleware.prepare(currentRequest, context: currentContext)
        }

        let initialResult: Result<RawResponse, NetworkError>
        let attemptStartedAt = self.now()
        var providedResponse: MiddlewareProvidedResponse?
        do {
          let response: RawResponse
          if let middlewareResponse = try await self.responseFromMiddleware(
            currentRequest,
            context: currentContext
          ) {
            providedResponse = middlewareResponse
            response = middlewareResponse.response
          } else {
            response = try await perform(currentRequest)
          }
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

        if let providedResponse {
          await self.startBackgroundRefreshIfNeeded(
            providedResponse: providedResponse,
            request: currentRequest,
            context: currentContext,
            perform: perform
          )
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
          await self.onRetry(currentContext.requestID, currentContext.attempt + 1, delay, currentRequest)
          currentRequest = retryRequest
          currentContext = currentContext.nextAttempt()
          continue
        }

        didFinish = true
        await self.finish(result: currentResult, request: currentRequest, context: currentContext)
        switch currentResult {
        case .success(let response):
          return response
        case .failure(let error):
          throw error
        }
      }
    } catch {
      let networkError = NetworkError.from(error)
      if !didFinish {
        await self.finish(result: .failure(networkError), request: currentRequest, context: currentContext)
      }
      throw networkError
    }
  }

  private func responseFromMiddleware(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareProvidedResponse? {
    for middleware in self.middleware {
      guard let responseProvider = middleware as? any ResponseProvidingMiddleware else {
        continue
      }
      if let response = try await responseProvider.respond(to: request, context: context) {
        return MiddlewareProvidedResponse(response: response, provider: responseProvider)
      }
    }
    return nil
  }

  private func startBackgroundRefreshIfNeeded(
    providedResponse: MiddlewareProvidedResponse,
    request: PreparedRequest,
    context: MiddlewareContext,
    perform: @escaping @Sendable (PreparedRequest) async throws(NetworkError) -> RawResponse
  ) async {
    guard let refreshProvider = providedResponse.provider as? any BackgroundRefreshingMiddleware else {
      return
    }

    let refreshRequestID = self.makeRequestID()
    let refreshContext = context.backgroundRefresh(
      requestID: refreshRequestID,
      startTime: self.now(),
      recordCacheEvent: { event in
        await self.onBackgroundCacheEvent(refreshRequestID, event)
      }
    )
    guard let refreshRequest = await refreshProvider.backgroundRefreshRequest(
      for: request,
      context: context,
      refreshContext: refreshContext
    ) else {
      return
    }

    await self.onBackgroundRefreshStarted(refreshRequestID, refreshRequest)
    Task {
      await self.executeBackgroundRefresh(
        refreshRequest,
        context: refreshContext,
        perform: perform
      )
    }
  }

  private func executeBackgroundRefresh(
    _ request: PreparedRequest,
    context: MiddlewareContext,
    perform: @escaping @Sendable (PreparedRequest) async throws(NetworkError) -> RawResponse
  ) async {
    var currentRequest = request
    var currentContext = context
    var didFinish = false

    do {
      while true {
        let initialResult: Result<RawResponse, NetworkError>
        let attemptStartedAt = self.now()
        do {
          initialResult = .success(try await perform(currentRequest))
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
          await self.onRetry(currentContext.requestID, currentContext.attempt + 1, delay, currentRequest)
          currentRequest = retryRequest
          currentContext = currentContext.nextAttempt()
          continue
        }

        didFinish = true
        await self.finish(result: currentResult, request: currentRequest, context: currentContext)
        let duration = context.startTime.duration(to: self.now())
        await self.onBackgroundRefreshCompleted(
          context.requestID,
          currentRequest,
          currentResult,
          duration
        )
        return
      }
    } catch {
      let networkError = NetworkError.from(error)
      if !didFinish {
        await self.finish(result: .failure(networkError), request: currentRequest, context: currentContext)
      }
      let duration = context.startTime.duration(to: self.now())
      await self.onBackgroundRefreshCompleted(
        context.requestID,
        currentRequest,
        .failure(networkError),
        duration
      )
    }
  }

  private func finish(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async {
    for middleware in self.middleware.reversed() {
      await middleware.finish(result: result, request: request, context: context)
    }
  }
}
