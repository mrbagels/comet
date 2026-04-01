import Foundation
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
}

private struct FailingWebSocketTransport: WebSocketTransport, Sendable {
  let error: NetworkError

  func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection {
    throw self.error
  }
}
