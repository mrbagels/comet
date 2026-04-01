public protocol HTTPTransport: Sendable {
  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse
}
