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

  /// Executes a prepared request directly, applying middleware, retries, and optional deduplication.
  public func sendPrepared(
    _ request: PreparedRequest,
    options: RequestOptions = .init()
  ) async throws(NetworkError) -> RawResponse {
    if let key = options.deduplicationKey {
      return try await self.deduplicator.deduplicate(key: key) {
        try await self.executeRequest(request, options: options)
      }
    } else {
      return try await self.executeRequest(request, options: options)
    }
  }

  private func performTransport(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    do {
      return try await self.transport.send(request)
    } catch {
      throw NetworkError.from(error)
    }
  }

  private func executeRequest(
    _ request: PreparedRequest,
    options: RequestOptions
  ) async throws(NetworkError) -> RawResponse {
    let requestID = self.configuration.makeRequestID()
    let context = MiddlewareContext(
      requestID: requestID,
      attempt: 0,
      startTime: self.configuration.now(),
      randomDouble: self.configuration.randomDouble
    )
    let traceRecorder = RequestTraceRecorder(
      id: requestID,
      metadata: request.metadata,
      method: request.method,
      url: request.url
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
        perform: self.performTransport
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

  private static func httpError(from response: RawResponse) -> NetworkError {
    .http(statusCode: response.statusCode, body: response.data, headers: response.headers)
  }
}

private actor RequestTraceRecorder {
  let id: UUID
  let metadata: RequestMetadata
  let method: HTTPMethod
  let url: URL
  private var attempts: [RequestTraceAttempt] = []
  private var pendingRetryDelays: [Int: Duration] = [:]

  init(
    id: UUID,
    metadata: RequestMetadata,
    method: HTTPMethod,
    url: URL
  ) {
    self.id = id
    self.metadata = metadata
    self.method = method
    self.url = url
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
      result: result
    )
  }
}

private struct FailingTransport: HTTPTransport, Sendable {
  let error: NetworkError

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    throw self.error
  }
}
