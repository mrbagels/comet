import Foundation
import HTTPTypes

/// Executes typed requests against a shared configuration and transport.
public struct HTTPClient: Sendable {
  private let configuration: ClientConfiguration
  private let transport: any HTTPTransport
  private let deduplicator: RequestDeduplicator
  private let broadcaster: EventBroadcaster<NetworkEvent>

  private init(
    configuration: ClientConfiguration,
    transport: any HTTPTransport,
    deduplicator: RequestDeduplicator,
    broadcaster: EventBroadcaster<NetworkEvent>
  ) {
    self.configuration = configuration
    self.transport = transport
    self.deduplicator = deduplicator
    self.broadcaster = broadcaster
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
      broadcaster: EventBroadcaster(bufferingPolicy: configuration.activityBufferingPolicy.asyncStreamPolicy)
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
    let prepared = try RequestBuilder.build(request, configuration: self.configuration)
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
    let chain = MiddlewareChain(
      middleware: self.configuration.middleware + options.middleware,
      sleep: self.configuration.sleep,
      onRetry: { id, attempt, delay in
        self.broadcaster.emit(.requestRetried(id: id, attempt: attempt, delay: delay, metadata: request.metadata))
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
      return response
    } catch {
      let networkError = NetworkError.from(error)
      let duration = context.startTime.duration(to: self.configuration.now())
      self.broadcaster.emit(.requestFailed(id: requestID, error: networkError, duration: duration, metadata: request.metadata))
      throw networkError
    }
  }

  private static func httpError(from response: RawResponse) -> NetworkError {
    .http(statusCode: response.statusCode, body: response.data, headers: response.headers)
  }
}

private struct FailingTransport: HTTPTransport, Sendable {
  let error: NetworkError

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    throw self.error
  }
}
