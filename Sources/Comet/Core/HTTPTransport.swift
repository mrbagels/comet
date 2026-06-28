/// Performs a prepared HTTP request and returns a raw HTTP response.
///
/// Conform this protocol to plug Comet into mocks, recorders, replay fixtures,
/// or future transports beyond the shipped ``URLSessionTransport``.
public protocol HTTPTransport: Sendable {
  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse
}

/// Optional transport capability for true streaming response bodies.
public protocol HTTPStreamingTransport: HTTPTransport {
  func stream(
    _ request: PreparedRequest,
    chunkSize: Int
  ) -> AsyncThrowingStream<HTTPStreamEvent, Error>
}

/// Optional transport capability for transfer progress callbacks.
public protocol HTTPProgressTransport: HTTPTransport {
  func send(
    _ request: PreparedRequest,
    progress: @escaping @Sendable (TransferProgress) async -> Void
  ) async throws(NetworkError) -> RawResponse
}
