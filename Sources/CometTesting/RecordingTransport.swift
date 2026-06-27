import Foundation
import Comet

/// Wraps another transport and records full request/response exchanges as it forwards traffic.
public actor RecordingTransport: HTTPTransport {
  private let base: any HTTPTransport
  private let now: @Sendable () -> Date
  private let redaction: RecordingRedaction
  private var exchanges: [RecordedExchange] = []

  /// Creates a recorder around another transport.
  public init(
    base: any HTTPTransport
  ) {
    self.base = base
    self.now = Date.init
    self.redaction = RecordingRedaction()
  }

  /// Creates a recorder around another transport with custom redaction rules.
  public init(
    base: any HTTPTransport,
    redaction: RecordingRedaction
  ) {
    self.base = base
    self.now = Date.init
    self.redaction = redaction
  }

  /// Creates a recorder around another transport with injectable time.
  public init(
    base: any HTTPTransport,
    now: @escaping @Sendable () -> Date
  ) {
    self.base = base
    self.now = now
    self.redaction = RecordingRedaction()
  }

  /// Creates a recorder around another transport with injectable time and custom redaction rules.
  public init(
    base: any HTTPTransport,
    now: @escaping @Sendable () -> Date,
    redaction: RecordingRedaction
  ) {
    self.base = base
    self.now = now
    self.redaction = redaction
  }

  /// Sends a request through the base transport and records the full outcome.
  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    let recordedAt = self.now()
    let start = ContinuousClock().now

    do {
      let response = try await self.base.send(request)
      self.exchanges.append(
        RecordedExchange(
          recordedAt: recordedAt,
          request: RecordedRequest(request, redaction: self.redaction),
          duration: start.duration(to: ContinuousClock().now),
          outcome: .success(RecordedResponse(response, redaction: self.redaction))
        )
      )
      return response
    } catch {
      let networkError = NetworkError.from(error)
      self.exchanges.append(
        RecordedExchange(
          recordedAt: recordedAt,
          request: RecordedRequest(request, redaction: self.redaction),
          duration: start.duration(to: ContinuousClock().now),
          outcome: .failure(RecordedNetworkError(networkError, redaction: self.redaction))
        )
      )
      throw networkError
    }
  }

  /// Returns the recorded requests in their original prepared form.
  public func recorded() -> [PreparedRequest] {
    self.exchanges.compactMap { try? $0.request.makePreparedRequest() }
  }

  /// Returns the recorded exchanges including duration and outcome details.
  public func recordedExchanges() -> [RecordedExchange] {
    self.exchanges
  }

  /// Packages the recorded exchanges into a serializable cassette.
  public func cassette() -> HTTPCassette {
    HTTPCassette(
      recordedAt: self.exchanges.first?.recordedAt ?? self.now(),
      exchanges: self.exchanges
    )
  }

  /// Writes the current recording session to a JSON cassette on disk.
  public func writeCassette(
    to url: URL,
    prettyPrinted: Bool = true
  ) throws {
    try self.cassette().write(to: url, prettyPrinted: prettyPrinted)
  }

  /// Clears all currently recorded exchanges.
  public func reset() {
    self.exchanges.removeAll()
  }
}
