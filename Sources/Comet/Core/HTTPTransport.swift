/// Performs a prepared HTTP request and returns a raw HTTP response.
///
/// Conform this protocol to plug Comet into mocks, recorders, replay fixtures,
/// or future transports beyond the shipped ``URLSessionTransport``.
public protocol HTTPTransport: Sendable {
  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse
}
