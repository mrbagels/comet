import Foundation
import Comet

public actor RecordingTransport: HTTPTransport {
  private let base: any HTTPTransport
  private let now: @Sendable () -> Date
  private var exchanges: [RecordedExchange] = []

  public init(
    base: any HTTPTransport,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.base = base
    self.now = now
  }

  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    let recordedAt = self.now()
    let start = ContinuousClock().now

    do {
      let response = try await self.base.send(request)
      self.exchanges.append(
        RecordedExchange(
          recordedAt: recordedAt,
          request: RecordedRequest(request),
          duration: start.duration(to: ContinuousClock().now),
          outcome: .success(RecordedResponse(response))
        )
      )
      return response
    } catch {
      let networkError = NetworkError.from(error)
      self.exchanges.append(
        RecordedExchange(
          recordedAt: recordedAt,
          request: RecordedRequest(request),
          duration: start.duration(to: ContinuousClock().now),
          outcome: .failure(RecordedNetworkError(networkError))
        )
      )
      throw networkError
    }
  }

  public func recorded() -> [PreparedRequest] {
    self.exchanges.compactMap { try? $0.request.makePreparedRequest() }
  }

  public func recordedExchanges() -> [RecordedExchange] {
    self.exchanges
  }

  public func cassette() -> HTTPCassette {
    HTTPCassette(
      recordedAt: self.exchanges.first?.recordedAt ?? self.now(),
      exchanges: self.exchanges
    )
  }

  public func writeCassette(
    to url: URL,
    prettyPrinted: Bool = true
  ) throws {
    try self.cassette().write(to: url, prettyPrinted: prettyPrinted)
  }

  public func reset() {
    self.exchanges.removeAll()
  }
}
