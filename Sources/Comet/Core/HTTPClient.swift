import Foundation
import HTTPTypes

/// Executes typed requests against a shared configuration and transport.
public struct HTTPClient: Sendable {
  private let configuration: ClientConfiguration
  private let transport: any HTTPTransport
  private let deduplicator: RequestDeduplicator
  private let broadcaster: EventBroadcaster<NetworkEvent>
  private let traceBroadcaster: EventBroadcaster<RequestTrace>

  private init(
    configuration: ClientConfiguration,
    transport: any HTTPTransport,
    deduplicator: RequestDeduplicator,
    broadcaster: EventBroadcaster<NetworkEvent>,
    traceBroadcaster: EventBroadcaster<RequestTrace>
  ) {
    self.configuration = configuration
    self.transport = transport
    self.deduplicator = deduplicator
    self.broadcaster = broadcaster
    self.traceBroadcaster = traceBroadcaster
  }

  /// Creates a client backed by a concrete live transport.
  public static func live(
    configuration: ClientConfiguration,
    transport: some HTTPTransport
  ) -> Self {
    Self(
      configuration: configuration,
      transport: transport,
      deduplicator: RequestDeduplicator(),
      broadcaster: EventBroadcaster(bufferingPolicy: configuration.activityBufferingPolicy.asyncStreamPolicy),
      traceBroadcaster: EventBroadcaster(
        bufferingPolicy: configuration.activityBufferingPolicy.asyncStreamPolicy(for: RequestTrace.self)
      )
    )
  }

  /// Creates a client that always fails with the provided error.
  public static func failing(with error: NetworkError) -> Self {
    Self.live(
      configuration: .default(baseURL: URL(string: "https://example.com")!),
      transport: FailingTransport(error: error)
    )
  }

  /// Streams request lifecycle events emitted by this client.
  public var activity: AsyncStream<NetworkEvent> {
    self.broadcaster.stream()
  }

  /// Streams completed request traces emitted by this client.
  public var traces: AsyncStream<RequestTrace> {
    self.traceBroadcaster.stream()
  }

  /// Resolves a typed request into the transport-ready request that will be sent.
  public func prepare<R: APIRequest>(_ request: R) throws(NetworkError) -> PreparedRequest {
    try RequestBuilder.build(request, configuration: self.configuration)
  }

  /// Sends a typed request, validates the HTTP status, and decodes the response.
  public func send<R: APIRequest>(_ request: R) async throws(NetworkError) -> R.Response {
    let response = try await self.sendRaw(request)
    guard request.options.statusValidation.contains(response.statusCode) else {
      throw Self.httpError(from: response)
    }
    return try request.responseSerializer.serialize(response, self.configuration)
  }

  /// Sends a typed request and decodes unsuccessful HTTP responses into the request's declared domain error type.
  public func sendWithTypedErrors<R: APIRequestWithErrorResponse>(
    _ request: R
  ) async throws(APIClientError<R.ErrorResponse>) -> R.Response {
    try await self.send(
      request,
      errorResponseSerializer: request.errorResponseSerializer
    )
  }

  /// Sends a typed request and decodes unsuccessful HTTP responses with the provided error serializer.
  public func send<R: APIRequest, ErrorResponse: Sendable>(
    _ request: R,
    errorResponseSerializer: ErrorResponseSerializer<ErrorResponse>
  ) async throws(APIClientError<ErrorResponse>) -> R.Response {
    let response: RawResponse
    do {
      response = try await self.sendRaw(request)
    } catch {
      throw .network(NetworkError.from(error))
    }

    guard request.options.statusValidation.contains(response.statusCode) else {
      let networkError = Self.httpError(from: response)

      do {
        let body = try errorResponseSerializer.serialize(response, self.configuration)
        throw APIClientError.api(
          DecodedErrorResponse(
            statusCode: response.statusCode,
            body: body,
            rawBody: response.data,
            headers: response.headers,
            networkError: networkError
          )
        )
      } catch let error as APIClientError<ErrorResponse> {
        throw error
      } catch {
        throw .errorResponseDecodingFailed(
          networkError: networkError,
          decodingError: NetworkError.from(error)
        )
      }
    }

    do {
      return try request.responseSerializer.serialize(response, self.configuration)
    } catch {
      throw .network(NetworkError.from(error))
    }
  }

  /// Sends a typed request and returns the raw HTTP response before status validation and decoding.
  public func sendRaw<R: APIRequest>(_ request: R) async throws(NetworkError) -> RawResponse {
    let prepared = try self.prepare(request)
    return try await self.sendPrepared(prepared, options: request.options)
  }

  /// Sends a typed request while receiving transfer progress from capable transports.
  public func sendRaw<R: APIRequest>(
    _ request: R,
    progress: @escaping @Sendable (TransferProgress) async -> Void
  ) async throws(NetworkError) -> RawResponse {
    let prepared = try self.prepare(request)
    return try await self.sendPrepared(prepared, options: request.options, progress: progress)
  }

  /// Executes a prepared request directly, applying middleware, retries, and optional deduplication.
  public func sendPrepared(
    _ request: PreparedRequest,
    options: RequestOptions = .init()
  ) async throws(NetworkError) -> RawResponse {
    try await self.sendPreparedInternal(request, options: options, progress: nil)
  }

  /// Executes a prepared request directly while receiving transfer progress from capable transports.
  public func sendPrepared(
    _ request: PreparedRequest,
    options: RequestOptions = .init(),
    progress: @escaping @Sendable (TransferProgress) async -> Void
  ) async throws(NetworkError) -> RawResponse {
    try await self.sendPreparedInternal(request, options: options, progress: progress)
  }

  private func sendPreparedInternal(
    _ request: PreparedRequest,
    options: RequestOptions,
    progress: (@Sendable (TransferProgress) async -> Void)?
  ) async throws(NetworkError) -> RawResponse {
    if let key = options.deduplicationKey {
      return try await self.deduplicator.deduplicate(key: key) {
        try await self.executeRequest(request, options: options, progress: progress)
      }
    } else {
      return try await self.executeRequest(request, options: options, progress: progress)
    }
  }

  /// Streams raw HTTP response events from transports that support streaming, falling back to buffered responses.
  public func stream<R: APIRequest>(
    _ request: R,
    chunkSize: Int = 16_384
  ) -> AsyncThrowingStream<HTTPStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        if let streamingTransport = self.transport as? any HTTPStreamingTransport {
          await self.streamWithStreamingTransport(
            request,
            transport: streamingTransport,
            chunkSize: chunkSize,
            continuation: continuation
          )
        } else {
          await self.streamWithBufferedTransport(
            request,
            continuation: continuation
          )
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  /// Streams response lines using the provided text encoding.
  public func lines<R: APIRequest>(
    _ request: R,
    encoding: String.Encoding = .utf8,
    chunkSize: Int = 16_384
  ) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var buffer = Data()
        var failedResponse: HTTPStreamResponse?
        var failureBody = Data()

        do {
          for try await event in self.stream(request, chunkSize: chunkSize) {
            switch event {
            case .response(let response):
              if !request.options.statusValidation.contains(response.statusCode) {
                failedResponse = response
              }

            case .bytes(let data):
              if failedResponse != nil {
                failureBody.append(data)
              } else {
                buffer.append(data)
                while let line = try Self.nextLine(from: &buffer, encoding: encoding) {
                  continuation.yield(line)
                }
              }

            case .complete:
              if let failedResponse {
                continuation.finish(
                  throwing: NetworkError.http(
                    statusCode: failedResponse.statusCode,
                    body: failureBody,
                    headers: failedResponse.headers
                  )
                )
                return
              }
              if !buffer.isEmpty {
                guard let line = String(data: buffer, encoding: encoding) else {
                  throw NetworkError.decoding(
                    DecodingError.dataCorrupted(
                      .init(codingPath: [], debugDescription: "Unable to decode streamed line.")
                    )
                  )
                }
                continuation.yield(line.trimmingTrailingCarriageReturn())
              }
              continuation.finish()
            }
          }
        } catch {
          continuation.finish(throwing: NetworkError.from(error))
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  /// Streams parsed Server-Sent Events frames.
  public func serverSentEvents<R: APIRequest>(
    _ request: R,
    encoding: String.Encoding = .utf8,
    chunkSize: Int = 16_384
  ) -> AsyncThrowingStream<ServerSentEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var parser = ServerSentEventParser()

        do {
          for try await line in self.lines(request, encoding: encoding, chunkSize: chunkSize) {
            if let event = parser.append(line) {
              continuation.yield(event)
            }
          }
          if let event = parser.finish() {
            continuation.yield(event)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: NetworkError.from(error))
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func performTransport(
    _ request: PreparedRequest,
    progress: (@Sendable (TransferProgress) async -> Void)? = nil
  ) async throws(NetworkError) -> RawResponse {
    do {
      if let progress, let transport = self.transport as? any HTTPProgressTransport {
        return try await transport.send(request, progress: progress)
      }

      if let progress, let body = request.body {
        await progress(
          TransferProgress(
            kind: .upload,
            completedBytes: Int64(body.count),
            totalBytes: Int64(body.count)
          )
        )
      }

      let response = try await self.transport.send(request)
      if let progress {
        await progress(
          TransferProgress(
            kind: .download,
            completedBytes: Int64(response.data.count),
            totalBytes: Int64(response.data.count)
          )
        )
      }
      return response
    } catch {
      throw NetworkError.from(error)
    }
  }

  private func executeRequest(
    _ request: PreparedRequest,
    options: RequestOptions,
    progress: (@Sendable (TransferProgress) async -> Void)? = nil
  ) async throws(NetworkError) -> RawResponse {
    let requestID = self.configuration.makeRequestID()
    let traceRecorder = RequestTraceRecorder(
      id: requestID,
      metadata: request.metadata,
      method: request.method,
      url: request.url,
      traceContext: request.metadata.traceContext
    )
    let context = MiddlewareContext(
      requestID: requestID,
      attempt: 0,
      startTime: self.configuration.now(),
      cachePolicy: options.cachePolicy,
      randomDouble: self.configuration.randomDouble,
      recordCacheEvent: { event in
        await traceRecorder.recordCacheEvent(event)
      }
    )
    let chain = MiddlewareChain(
      middleware: self.configuration.middleware + options.middleware,
      sleep: self.configuration.sleep,
      onRetry: { id, attempt, delay in
        await traceRecorder.recordRetry(afterAttempt: attempt, delay: delay)
        self.broadcaster.emit(.requestRetried(id: id, attempt: attempt, delay: delay, metadata: request.metadata))
      },
      now: self.configuration.now,
      onAttempt: { _, attempt, preparedRequest, result, duration in
        await traceRecorder.recordAttempt(
          number: attempt,
          request: preparedRequest,
          result: result,
          duration: duration
        )
      }
    )

    self.broadcaster.emit(.requestStarted(id: requestID, method: request.method, url: request.url, metadata: request.metadata))
    do {
      let response = try await chain.execute(
        request,
        context: context,
        perform: { (preparedRequest: PreparedRequest) async throws(NetworkError) -> RawResponse in
          try await self.performTransport(preparedRequest, progress: progress)
        }
      )
      let duration = context.startTime.duration(to: self.configuration.now())
      self.broadcaster.emit(.requestCompleted(id: requestID, statusCode: response.statusCode, duration: duration, metadata: request.metadata))
      self.traceBroadcaster.emit(
        await traceRecorder.makeTrace(
          duration: duration,
          result: .success(statusCode: response.statusCode, responseBytes: response.data.count)
        )
      )
      return response
    } catch {
      let networkError = NetworkError.from(error)
      let duration = context.startTime.duration(to: self.configuration.now())
      self.broadcaster.emit(.requestFailed(id: requestID, error: networkError, duration: duration, metadata: request.metadata))
      self.traceBroadcaster.emit(
        await traceRecorder.makeTrace(
          duration: duration,
          result: .failure(networkError)
        )
      )
      throw networkError
    }
  }

  private func streamWithBufferedTransport<R: APIRequest>(
    _ request: R,
    continuation: AsyncThrowingStream<HTTPStreamEvent, Error>.Continuation
  ) async {
    do {
      let response = try await self.sendRaw(request)
      continuation.yield(
        .response(
          HTTPStreamResponse(
            statusCode: response.statusCode,
            headers: response.headers
          )
        )
      )
      if !response.data.isEmpty {
        continuation.yield(.bytes(response.data))
      }
      continuation.yield(.complete)
      continuation.finish()
    } catch {
      continuation.finish(throwing: NetworkError.from(error))
    }
  }

  private func streamWithStreamingTransport<R: APIRequest>(
    _ request: R,
    transport: any HTTPStreamingTransport,
    chunkSize: Int,
    continuation: AsyncThrowingStream<HTTPStreamEvent, Error>.Continuation
  ) async {
    let middleware = self.configuration.middleware + request.options.middleware
    do {
      let prepared = try self.prepare(request)
      let requestID = self.configuration.makeRequestID()
      let traceRecorder = RequestTraceRecorder(
        id: requestID,
        metadata: prepared.metadata,
        method: prepared.method,
        url: prepared.url,
        traceContext: prepared.metadata.traceContext
      )
      let context = MiddlewareContext(
        requestID: requestID,
        attempt: 0,
        startTime: self.configuration.now(),
        cachePolicy: request.options.cachePolicy,
        randomDouble: self.configuration.randomDouble,
        recordCacheEvent: { event in
          await traceRecorder.recordCacheEvent(event)
        }
      )
      var currentRequest = prepared
      self.broadcaster.emit(
        .requestStarted(
          id: requestID,
          method: prepared.method,
          url: prepared.url,
          metadata: prepared.metadata
        )
      )

      let startedAt = self.configuration.now()
      var responseMetadata: HTTPStreamResponse?
      var responseBytes = 0
      var didComplete = false

      do {
        for middleware in middleware {
          currentRequest = try await middleware.prepare(currentRequest, context: context)
        }

        if let middlewareResponse = try await self.responseFromMiddleware(
          middleware: middleware,
          request: currentRequest,
          context: context
        ) {
          let attemptDuration = startedAt.duration(to: self.configuration.now())
          await traceRecorder.recordAttempt(
            number: 1,
            request: currentRequest,
            result: .success(middlewareResponse),
            duration: attemptDuration
          )
          await self.finish(
            middleware: middleware,
            result: .success(middlewareResponse),
            request: currentRequest,
            context: context
          )
          self.yieldBufferedResponse(middlewareResponse, to: continuation)

          let duration = startedAt.duration(to: self.configuration.now())
          self.broadcaster.emit(
            .requestCompleted(
              id: requestID,
              statusCode: middlewareResponse.statusCode,
              duration: duration,
              metadata: currentRequest.metadata
            )
          )
          self.traceBroadcaster.emit(
            await traceRecorder.makeTrace(
              duration: duration,
              result: .success(statusCode: middlewareResponse.statusCode, responseBytes: middlewareResponse.data.count)
            )
          )
          continuation.finish()
          return
        }

        for try await event in transport.stream(currentRequest, chunkSize: max(1, chunkSize)) {
          switch event {
          case .response(let response):
            responseMetadata = response
          case .bytes(let data):
            responseBytes += data.count
          case .complete:
            didComplete = true
          }
          continuation.yield(event)
        }

        if !didComplete {
          continuation.yield(.complete)
        }

        let duration = startedAt.duration(to: self.configuration.now())
        let statusCode = responseMetadata?.statusCode ?? 0
        let summaryResponse = RawResponse(
          data: Data(),
          statusCode: statusCode,
          headers: responseMetadata?.headers ?? HTTPFields()
        )
        await traceRecorder.recordAttempt(
          number: 1,
          request: currentRequest,
          result: .success(summaryResponse),
          duration: duration
        )
        await self.finish(
          middleware: middleware,
          result: .success(summaryResponse),
          request: currentRequest,
          context: context
        )
        self.broadcaster.emit(
          .requestCompleted(
            id: requestID,
            statusCode: statusCode,
            duration: duration,
            metadata: currentRequest.metadata
          )
        )
        self.traceBroadcaster.emit(
          await traceRecorder.makeTrace(
            duration: duration,
            result: .success(statusCode: statusCode, responseBytes: responseBytes),
          )
        )
        continuation.finish()
      } catch {
        let networkError = NetworkError.from(error)
        let duration = startedAt.duration(to: self.configuration.now())
        await traceRecorder.recordAttempt(
          number: 1,
          request: currentRequest,
          result: .failure(networkError),
          duration: duration
        )
        await self.finish(
          middleware: middleware,
          result: .failure(networkError),
          request: currentRequest,
          context: context
        )
        self.broadcaster.emit(
          .requestFailed(
            id: requestID,
            error: networkError,
            duration: duration,
            metadata: currentRequest.metadata
          )
        )
        self.traceBroadcaster.emit(
          await traceRecorder.makeTrace(
            duration: duration,
            result: .failure(networkError),
          )
        )
        continuation.finish(throwing: networkError)
      }
    } catch {
      continuation.finish(throwing: NetworkError.from(error))
    }
  }

  private func responseFromMiddleware(
    middleware: [any Middleware],
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> RawResponse? {
    for middleware in middleware {
      guard let responseProvider = middleware as? any ResponseProvidingMiddleware else {
        continue
      }
      if let response = try await responseProvider.respond(to: request, context: context) {
        return response
      }
    }
    return nil
  }

  private func finish(
    middleware: [any Middleware],
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async {
    for middleware in middleware.reversed() {
      await middleware.finish(result: result, request: request, context: context)
    }
  }

  private func yieldBufferedResponse(
    _ response: RawResponse,
    to continuation: AsyncThrowingStream<HTTPStreamEvent, Error>.Continuation
  ) {
    continuation.yield(
      .response(
        HTTPStreamResponse(
          statusCode: response.statusCode,
          headers: response.headers
        )
      )
    )
    if !response.data.isEmpty {
      continuation.yield(.bytes(response.data))
    }
    continuation.yield(.complete)
  }

  private static func nextLine(
    from buffer: inout Data,
    encoding: String.Encoding
  ) throws(NetworkError) -> String? {
    guard let newlineIndex = buffer.firstIndex(of: 0x0A) else { return nil }
    var lineData = buffer[..<newlineIndex]
    if lineData.last == 0x0D {
      lineData = lineData.dropLast()
    }
    buffer.removeSubrange(buffer.startIndex...newlineIndex)

    guard let line = String(data: Data(lineData), encoding: encoding) else {
      throw .decoding(
        DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "Unable to decode streamed line.")
        )
      )
    }
    return line
  }

  private static func httpError(from response: RawResponse) -> NetworkError {
    .http(statusCode: response.statusCode, body: response.data, headers: response.headers)
  }
}

private struct ServerSentEventParser {
  private var event: String?
  private var id: String?
  private var dataLines: [String] = []
  private var retryMilliseconds: Int?

  mutating func append(_ line: String) -> ServerSentEvent? {
    if line.isEmpty {
      return self.flush()
    }
    if line.hasPrefix(":") {
      return nil
    }

    let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let field = String(parts.first ?? "")
    var value = parts.count > 1 ? String(parts[1]) : ""
    if value.first == " " {
      value.removeFirst()
    }

    switch field {
    case "event":
      self.event = value
    case "id":
      self.id = value
    case "data":
      self.dataLines.append(value)
    case "retry":
      self.retryMilliseconds = Int(value)
    default:
      break
    }

    return nil
  }

  mutating func finish() -> ServerSentEvent? {
    self.flush()
  }

  private mutating func flush() -> ServerSentEvent? {
    guard self.event != nil || self.id != nil || !self.dataLines.isEmpty || self.retryMilliseconds != nil else {
      return nil
    }

    let event = ServerSentEvent(
      event: self.event,
      id: self.id,
      data: self.dataLines.joined(separator: "\n"),
      retryMilliseconds: self.retryMilliseconds
    )
    self.event = nil
    self.id = nil
    self.dataLines.removeAll()
    self.retryMilliseconds = nil
    return event
  }
}

private extension String {
  func trimmingTrailingCarriageReturn() -> String {
    guard self.last == "\r" else { return self }
    return String(self.dropLast())
  }
}

private actor RequestTraceRecorder {
  let id: UUID
  let metadata: RequestMetadata
  let method: HTTPMethod
  let url: URL
  private var traceContext: TraceContext?
  private var cacheEvents: [RequestCacheTraceEvent] = []
  private var attempts: [RequestTraceAttempt] = []
  private var pendingRetryDelays: [Int: Duration] = [:]

  init(
    id: UUID,
    metadata: RequestMetadata,
    method: HTTPMethod,
    url: URL,
    traceContext: TraceContext?
  ) {
    self.id = id
    self.metadata = metadata
    self.method = method
    self.url = url
    self.traceContext = traceContext
  }

  func recordAttempt(
    number: Int,
    request: PreparedRequest,
    result: Result<RawResponse, NetworkError>,
    duration: Duration
  ) {
    let responseStatusCode: Int?
    let responseBytes: Int?
    let error: NetworkError?

    switch result {
    case .success(let response):
      responseStatusCode = response.statusCode
      responseBytes = response.data.count
      error = nil
    case .failure(let networkError):
      responseStatusCode = nil
      responseBytes = nil
      error = networkError
    }

    if self.traceContext == nil {
      self.traceContext = request.propagatedTraceContext
    }

    self.attempts.append(
      RequestTraceAttempt(
        number: number,
        method: request.method,
        url: request.url,
        requestBytes: request.body?.count ?? 0,
        responseStatusCode: responseStatusCode,
        responseBytes: responseBytes,
        error: error,
        duration: duration,
        retryDelay: self.pendingRetryDelays[number]
      )
    )
    self.pendingRetryDelays[number] = nil
  }

  func recordRetry(afterAttempt attempt: Int, delay: Duration) {
    guard let index = self.attempts.lastIndex(where: { $0.number == attempt }) else {
      self.pendingRetryDelays[attempt] = delay
      return
    }

    self.attempts[index].retryDelay = delay
  }

  func recordCacheEvent(_ event: RequestCacheTraceEvent) {
    self.cacheEvents.append(event)
  }

  func makeTrace(
    duration: Duration,
    result: RequestTraceResult
  ) -> RequestTrace {
    RequestTrace(
      id: self.id,
      metadata: self.metadata,
      method: self.method,
      url: self.url,
      attempts: self.attempts,
      duration: duration,
      result: result,
      traceContext: self.traceContext,
      cacheEvents: self.cacheEvents
    )
  }
}

private struct FailingTransport: HTTPTransport, Sendable {
  let error: NetworkError

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    throw self.error
  }
}
