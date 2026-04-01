import Foundation
import Comet

/// An in-memory WebSocket transport for deterministic tests and demos.
public actor MockWebSocketTransport: WebSocketTransport {
  private struct SessionState: Sendable {
    var incomingMessages: [WebSocketMessage]
    var sentMessages: [WebSocketMessage] = []
    var pingCount = 0
    var closeFrame: WebSocketCloseFrame?
  }

  private let selectedSubprotocol: String?
  private let initialIncomingMessages: [WebSocketMessage]
  private let echoSentMessages: Bool
  private let connectError: NetworkError?

  private var connectRequestsStorage: [WebSocketRequest] = []
  private var sessions: [UUID: SessionState] = [:]

  /// Creates a mock WebSocket transport with optional preloaded incoming messages.
  public init(
    incomingMessages: [WebSocketMessage] = [],
    selectedSubprotocol: String? = nil,
    echoSentMessages: Bool = false,
    connectError: NetworkError? = nil
  ) {
    self.initialIncomingMessages = incomingMessages
    self.selectedSubprotocol = selectedSubprotocol
    self.echoSentMessages = echoSentMessages
    self.connectError = connectError
  }

  /// Connects a WebSocket request using the configured in-memory behavior.
  public func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection {
    if let connectError {
      throw connectError
    }

    let sessionID = UUID()
    self.connectRequestsStorage.append(request)
    self.sessions[sessionID] = SessionState(incomingMessages: self.initialIncomingMessages)

    return WebSocketConnection(
      selectedSubprotocol: self.selectedSubprotocol,
      send: { [transport = self] message in
        try await transport.send(message, sessionID: sessionID)
      },
      receive: { [transport = self] in
        try await transport.receive(sessionID: sessionID)
      },
      ping: { [transport = self] in
        try await transport.ping(sessionID: sessionID)
      },
      close: { [transport = self] code, reason in
        try await transport.close(code: code, reason: reason, sessionID: sessionID)
      }
    )
  }

  /// Returns the recorded connect requests.
  public func connectRequests() -> [WebSocketRequest] {
    self.connectRequestsStorage
  }

  /// Returns every message sent across all mock sessions.
  public func sentMessages() -> [WebSocketMessage] {
    self.sessions.values.flatMap(\.sentMessages)
  }

  /// Returns the total number of ping frames sent across all mock sessions.
  public func pingCount() -> Int {
    self.sessions.values.reduce(0) { partialResult, session in
      partialResult + session.pingCount
    }
  }

  /// Returns the close frames recorded across all mock sessions.
  public func closeFrames() -> [WebSocketCloseFrame] {
    self.sessions.values.compactMap(\.closeFrame)
  }

  /// Enqueues an incoming message for all currently open mock sessions.
  public func enqueueIncoming(_ message: WebSocketMessage) {
    for sessionID in self.sessions.keys {
      self.sessions[sessionID]?.incomingMessages.append(message)
    }
  }

  private func send(
    _ message: WebSocketMessage,
    sessionID: UUID
  ) throws(NetworkError) {
    var session = try self.requireSession(id: sessionID)
    session.sentMessages.append(message)
    if self.echoSentMessages {
      session.incomingMessages.append(message)
    }
    self.sessions[sessionID] = session
  }

  private func receive(sessionID: UUID) throws(NetworkError) -> WebSocketMessage {
    var session = try self.requireSession(id: sessionID)

    guard !session.incomingMessages.isEmpty else {
      throw NetworkError.invalidRequest("No mocked WebSocket message is queued for this session.")
    }

    let message = session.incomingMessages.removeFirst()
    self.sessions[sessionID] = session
    return message
  }

  private func ping(sessionID: UUID) throws(NetworkError) {
    var session = try self.requireSession(id: sessionID)
    session.pingCount += 1
    self.sessions[sessionID] = session
  }

  private func close(
    code: WebSocketCloseCode,
    reason: Data?,
    sessionID: UUID
  ) throws(NetworkError) {
    var session = try self.requireSession(id: sessionID)
    session.closeFrame = WebSocketCloseFrame(code: code, reason: reason)
    self.sessions[sessionID] = session
  }

  private func requireSession(id: UUID) throws(NetworkError) -> SessionState {
    guard let session = self.sessions[id] else {
      throw NetworkError.invalidRequest("Mock WebSocket session is unavailable.")
    }

    if let closeFrame = session.closeFrame {
      throw NetworkError.webSocketClosed(code: closeFrame.code, reason: closeFrame.reason)
    }

    return session
  }
}
