import Comet

public actor RecordingTransport: HTTPTransport {
  private let base: any HTTPTransport
  private var recordedRequests: [PreparedRequest] = []

  public init(base: any HTTPTransport) {
    self.base = base
  }

  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    self.recordedRequests.append(request)
    return try await self.base.send(request)
  }

  public func recorded() -> [PreparedRequest] {
    self.recordedRequests
  }

  public func reset() {
    self.recordedRequests.removeAll()
  }
}
