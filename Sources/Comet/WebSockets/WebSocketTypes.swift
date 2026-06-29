import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HTTPTypes

/// Describes a WebSocket handshake request.
public struct WebSocketRequest: Sendable {
  public var url: URL
  public var headers: HTTPFields
  public var subprotocols: [String]
  public var maximumMessageSize: Int
  public var timeout: Duration?

  /// Creates a WebSocket request with optional headers and subprotocol negotiation.
  public init(
    url: URL,
    headers: HTTPFields = .init(),
    subprotocols: [String] = [],
    maximumMessageSize: Int = 1_048_576,
    timeout: Duration? = nil
  ) {
    self.url = url
    self.headers = headers
    self.subprotocols = subprotocols
    self.maximumMessageSize = maximumMessageSize
    self.timeout = timeout
  }

  /// Bridges the request to ``Foundation/URLRequest`` for transport implementations that need it.
  public var urlRequest: URLRequest {
    var request = URLRequest(url: self.url)
    request.allHTTPHeaderFields = self.headers.combinedForFoundation

    if !self.subprotocols.isEmpty {
      request.setValue(self.subprotocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
    }

    if let timeout {
      request.timeoutInterval = timeout.timeInterval
    }

    return request
  }
}

/// Represents a single WebSocket message payload.
public enum WebSocketMessage: Sendable, Equatable {
  case text(String)
  case data(Data)
}

/// Represents a WebSocket close code while preserving support for custom application codes.
public struct WebSocketCloseCode: RawRepresentable, Sendable, Hashable, ExpressibleByIntegerLiteral, CustomStringConvertible {
  public let rawValue: UInt16

  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  public init(integerLiteral value: UInt16) {
    self.init(rawValue: value)
  }

  public var description: String {
    String(self.rawValue)
  }

  public static let invalid: Self = 0
  public static let normalClosure: Self = 1000
  public static let goingAway: Self = 1001
  public static let protocolError: Self = 1002
  public static let unsupportedData: Self = 1003
  public static let noStatusReceived: Self = 1005
  public static let abnormalClosure: Self = 1006
  public static let invalidFramePayloadData: Self = 1007
  public static let policyViolation: Self = 1008
  public static let messageTooBig: Self = 1009
  public static let mandatoryExtensionMissing: Self = 1010
  public static let internalServerError: Self = 1011
  public static let tlsHandshakeFailure: Self = 1015
}

/// Describes a WebSocket close frame.
public struct WebSocketCloseFrame: Sendable, Hashable {
  public var code: WebSocketCloseCode
  public var reason: Data?

  public init(
    code: WebSocketCloseCode = .normalClosure,
    reason: Data? = nil
  ) {
    self.code = code
    self.reason = reason
  }

  /// Returns the close reason as UTF-8 text when possible.
  public var reasonString: String? {
    guard let reason else { return nil }
    return String(data: reason, encoding: .utf8)
  }
}

/// A live WebSocket connection returned by a ``WebSocketTransport``.
public struct WebSocketConnection: Sendable {
  public let selectedSubprotocol: String?

  private let sendHandler: @Sendable (WebSocketMessage) async throws -> Void
  private let receiveHandler: @Sendable () async throws -> WebSocketMessage
  private let pingHandler: @Sendable () async throws -> Void
  private let closeHandler: @Sendable (WebSocketCloseCode, Data?) async throws -> Void

  /// Creates a type-erased WebSocket connection from transport-provided operations.
  public init(
    selectedSubprotocol: String? = nil,
    send: @escaping @Sendable (WebSocketMessage) async throws -> Void,
    receive: @escaping @Sendable () async throws -> WebSocketMessage,
    ping: @escaping @Sendable () async throws -> Void,
    close: @escaping @Sendable (WebSocketCloseCode, Data?) async throws -> Void
  ) {
    self.selectedSubprotocol = selectedSubprotocol
    self.sendHandler = send
    self.receiveHandler = receive
    self.pingHandler = ping
    self.closeHandler = close
  }

  /// Sends a single WebSocket message.
  public func send(_ message: WebSocketMessage) async throws(NetworkError) {
    do {
      try await self.sendHandler(message)
    } catch {
      throw .from(error)
    }
  }

  /// Receives the next WebSocket message from the remote peer.
  public func receive() async throws(NetworkError) -> WebSocketMessage {
    do {
      return try await self.receiveHandler()
    } catch {
      throw .from(error)
    }
  }

  /// Returns a stream that repeatedly receives WebSocket messages until the connection throws.
  public func messages() -> AsyncThrowingStream<WebSocketMessage, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          while !Task.isCancelled {
            continuation.yield(try await self.receive())
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  /// Sends a ping frame and waits for the pong acknowledgement.
  public func ping() async throws(NetworkError) {
    do {
      try await self.pingHandler()
    } catch {
      throw .from(error)
    }
  }

  /// Closes the WebSocket connection with the provided close code and optional reason.
  public func close(
    code: WebSocketCloseCode = .normalClosure,
    reason: Data? = nil
  ) async throws(NetworkError) {
    do {
      try await self.closeHandler(code, reason)
    } catch {
      throw .from(error)
    }
  }
}

/// Reconnect behavior for ``WebSocketSession``.
public struct WebSocketSessionConfiguration: Sendable {
  public var maximumReconnectAttempts: Int
  public var reconnectDelay: @Sendable (Int) -> Duration
  public var sleep: @Sendable (Duration) async throws -> Void

  public init(
    maximumReconnectAttempts: Int = 3,
    reconnectDelay: @escaping @Sendable (Int) -> Duration = { _ in .seconds(1) },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
      try await Task.sleep(for: duration)
    }
  ) {
    self.maximumReconnectAttempts = maximumReconnectAttempts
    self.reconnectDelay = reconnectDelay
    self.sleep = sleep
  }
}

/// High-level WebSocket session events.
public enum WebSocketSessionEvent: Sendable {
  case connected(selectedSubprotocol: String?)
  case message(WebSocketMessage)
  case disconnected(NetworkError)
  case reconnecting(attempt: Int, delay: Duration)
}

/// A resilient session wrapper over a low-level ``WebSocketConnection``.
public actor WebSocketSession {
  private let client: WebSocketClient
  private let request: WebSocketRequest
  private let configuration: WebSocketSessionConfiguration

  private var connection: WebSocketConnection?
  private var isClosed = false

  public init(
    client: WebSocketClient,
    request: WebSocketRequest,
    configuration: WebSocketSessionConfiguration = .init()
  ) {
    self.client = client
    self.request = request
    self.configuration = configuration
  }

  /// Connects the session if needed and returns the current connection.
  public func connect() async throws(NetworkError) -> WebSocketConnection {
    if let connection {
      return connection
    }

    return try await self.connectFresh()
  }

  /// Sends a message through the current connection, reconnecting once when configured.
  public func send(_ message: WebSocketMessage) async throws(NetworkError) {
    do {
      try await self.connect().send(message)
    } catch {
      self.connection = nil
      guard self.configuration.maximumReconnectAttempts > 0 else {
        throw .from(error)
      }
      try await self.connectFresh().send(message)
    }
  }

  /// Sends a ping frame through the current connection.
  public func ping() async throws(NetworkError) {
    try await self.connect().ping()
  }

  /// Closes the current connection and prevents future event-stream reconnects.
  public func close(
    code: WebSocketCloseCode = .normalClosure,
    reason: Data? = nil
  ) async throws(NetworkError) {
    self.isClosed = true
    if let connection {
      try await connection.close(code: code, reason: reason)
    }
    self.connection = nil
  }

  /// Streams session lifecycle events, including reconnect attempts and messages.
  public nonisolated func events() -> AsyncThrowingStream<WebSocketSessionEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        await self.runEvents(continuation: continuation)
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  /// Streams only messages from ``events()``.
  public nonisolated func messages() -> AsyncThrowingStream<WebSocketMessage, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await event in self.events() {
            if case .message(let message) = event {
              continuation.yield(message)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func connectFresh() async throws(NetworkError) -> WebSocketConnection {
    self.isClosed = false
    let connection = try await self.client.connect(self.request)
    self.connection = connection
    return connection
  }

  private func runEvents(
    continuation: AsyncThrowingStream<WebSocketSessionEvent, Error>.Continuation
  ) async {
    var reconnectAttempts = 0

    while !Task.isCancelled {
      guard !self.isClosed else {
        continuation.finish()
        return
      }

      do {
        let connection = try await self.connectFresh()
        continuation.yield(.connected(selectedSubprotocol: connection.selectedSubprotocol))

        while !Task.isCancelled && !self.isClosed {
          continuation.yield(.message(try await connection.receive()))
        }

        continuation.finish()
        return
      } catch {
        let networkError = NetworkError.from(error)
        self.connection = nil

        guard !self.isClosed else {
          continuation.finish()
          return
        }

        continuation.yield(.disconnected(networkError))

        guard reconnectAttempts < self.configuration.maximumReconnectAttempts else {
          continuation.finish(throwing: networkError)
          return
        }

        reconnectAttempts += 1
        let delay = self.configuration.reconnectDelay(reconnectAttempts)
        continuation.yield(.reconnecting(attempt: reconnectAttempts, delay: delay))

        do {
          if delay > .zero {
            try await self.configuration.sleep(delay)
          }
        } catch {
          continuation.finish(throwing: NetworkError.from(error))
          return
        }
      }
    }

    continuation.finish()
  }
}

/// Connects a ``WebSocketRequest`` and returns a live ``WebSocketConnection``.
public protocol WebSocketTransport: Sendable {
  func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection
}

/// The main execution boundary for WebSocket connections in Comet.
public struct WebSocketClient: Sendable {
  private let transport: any WebSocketTransport

  private init(transport: any WebSocketTransport) {
    self.transport = transport
  }

  /// Creates a client backed by a concrete transport.
  public static func live(transport: some WebSocketTransport) -> Self {
    Self(transport: transport)
  }

  /// Creates a client that always fails to connect with the provided error.
  public static func failing(with error: NetworkError) -> Self {
    Self(transport: FailingWebSocketTransport(error: error))
  }

  /// Connects a WebSocket request using the configured transport.
  public func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection {
    try await self.transport.connect(request)
  }

  /// Creates a resilient session wrapper for a WebSocket request.
  public func session(
    for request: WebSocketRequest,
    configuration: WebSocketSessionConfiguration = .init()
  ) -> WebSocketSession {
    WebSocketSession(client: self, request: request, configuration: configuration)
  }
}

private struct FailingWebSocketTransport: WebSocketTransport, Sendable {
  let error: NetworkError

  func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection {
    throw self.error
  }
}
