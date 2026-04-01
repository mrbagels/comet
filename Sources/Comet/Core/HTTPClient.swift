import Foundation
import HTTPTypes

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

  public static func live(
    configuration: ClientConfiguration,
    transport: some HTTPTransport
  ) -> Self {
    Self(
      configuration: configuration,
      transport: transport,
      deduplicator: RequestDeduplicator(),
      broadcaster: EventBroadcaster()
    )
  }

  public static func failing(with error: NetworkError) -> Self {
    Self.live(
      configuration: .default(baseURL: URL(string: "https://example.com")!),
      transport: FailingTransport(error: error)
    )
  }

  public var activity: AsyncStream<NetworkEvent> {
    self.broadcaster.stream()
  }

  public func send<R: APIRequest>(_ request: R) async throws(NetworkError) -> R.Response {
    let response = try await self.sendRaw(request)
    guard request.options.statusValidation.contains(response.statusCode) else {
      throw .http(statusCode: response.statusCode, body: response.data, headers: response.headers)
    }
    return try request.responseSerializer.serialize(response, self.configuration)
  }

  public func sendRaw<R: APIRequest>(_ request: R) async throws(NetworkError) -> RawResponse {
    let prepared = try RequestBuilder.build(request, configuration: self.configuration)
    return try await self.sendPrepared(prepared, options: request.options)
  }

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
        self.broadcaster.emit(.requestRetried(id: id, attempt: attempt, delay: delay))
      }
    )

    self.broadcaster.emit(.requestStarted(id: requestID, method: request.method, url: request.url))
    do {
      let response = try await chain.execute(
        request,
        context: context,
        perform: self.performTransport
      )
      let duration = context.startTime.duration(to: self.configuration.now())
      self.broadcaster.emit(.requestCompleted(id: requestID, statusCode: response.statusCode, duration: duration))
      return response
    } catch {
      let networkError = NetworkError.from(error)
      let duration = context.startTime.duration(to: self.configuration.now())
      self.broadcaster.emit(.requestFailed(id: requestID, error: networkError, duration: duration))
      throw networkError
    }
  }
}

private struct FailingTransport: HTTPTransport, Sendable {
  let error: NetworkError

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    throw self.error
  }
}
