import Foundation
import HTTPTypes
import Testing
@testable import Comet

private actor TestSocketState {
  private(set) var sentMessages: [WebSocketMessage] = []
  private(set) var pingCount = 0
  private(set) var closeFrames: [WebSocketCloseFrame] = []

  func recordSend(_ message: WebSocketMessage) {
    self.sentMessages.append(message)
  }

  func recordPing() {
    self.pingCount += 1
  }

  func recordClose(_ frame: WebSocketCloseFrame) {
    self.closeFrames.append(frame)
  }
}

private actor QueuedSocketState {
  private var incomingMessages: [WebSocketMessage]

  init(incomingMessages: [WebSocketMessage]) {
    self.incomingMessages = incomingMessages
  }

  func nextMessage() throws(NetworkError) -> WebSocketMessage {
    guard !self.incomingMessages.isEmpty else {
      throw .webSocketClosed(code: .normalClosure, reason: Data("done".utf8))
    }

    return self.incomingMessages.removeFirst()
  }
}

private struct TestWebSocketTransport: WebSocketTransport, Sendable {
  let state: TestSocketState

  func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection {
    WebSocketConnection(
      selectedSubprotocol: "comet-demo",
      send: { message in
        await self.state.recordSend(message)
      },
      receive: {
        .text("socket-ack")
      },
      ping: {
        await self.state.recordPing()
      },
      close: { code, reason in
        await self.state.recordClose(WebSocketCloseFrame(code: code, reason: reason))
      }
    )
  }
}

private struct QueuedWebSocketTransport: WebSocketTransport, Sendable {
  let state: QueuedSocketState

  func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection {
    WebSocketConnection(
      send: { _ in },
      receive: {
        try await self.state.nextMessage()
      },
      ping: {},
      close: { _, _ in }
    )
  }
}

private actor ReconnectingSocketState {
  private var connectCountValue = 0

  func connect() -> WebSocketConnection {
    self.connectCountValue += 1
    let messages: [WebSocketMessage] = self.connectCountValue == 1
      ? [.text("first")]
      : [.text("second")]
    let connectionState = QueuedSocketState(incomingMessages: messages)

    return WebSocketConnection(
      selectedSubprotocol: "comet-demo",
      send: { _ in },
      receive: {
        try await connectionState.nextMessage()
      },
      ping: {},
      close: { _, _ in }
    )
  }

  func connectCount() -> Int {
    self.connectCountValue
  }
}

private actor SleepGate {
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func sleep() async {
    await withCheckedContinuation { continuation in
      self.waiters.append(continuation)
    }
  }

  func resumeAll() {
    let waiters = self.waiters
    self.waiters = []
    for waiter in waiters {
      waiter.resume()
    }
  }
}

private struct ReconnectingWebSocketTransport: WebSocketTransport, Sendable {
  let state: ReconnectingSocketState

  func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection {
    await self.state.connect()
  }
}

@Test func webSocketRequestBuildsURLRequestWithHeadersAndProtocols() {
  var headers = HTTPFields()
  headers[.authorization] = "Bearer token"

  let request = WebSocketRequest(
    url: URL(string: "wss://example.com/socket")!,
    headers: headers,
    subprotocols: ["chat", "comet.v1"],
    timeout: .seconds(5)
  )

  let urlRequest = request.urlRequest

  #expect(urlRequest.url?.absoluteString == "wss://example.com/socket")
  #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
  #expect(urlRequest.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "chat, comet.v1")
  #expect(urlRequest.timeoutInterval == 5)
}

@Test func webSocketClientConnectsAndUsesTransportOperations() async throws {
  let state = TestSocketState()
  let client = WebSocketClient.live(transport: TestWebSocketTransport(state: state))

  let connection = try await client.connect(
    WebSocketRequest(url: URL(string: "wss://example.com/socket")!)
  )

  #expect(connection.selectedSubprotocol == "comet-demo")

  try await connection.send(.text("hello"))
  try await connection.ping()
  let response = try await connection.receive()
  try await connection.close(code: .goingAway, reason: Data("bye".utf8))

  #expect(response == .text("socket-ack"))
  #expect(await state.sentMessages == [.text("hello")])
  #expect(await state.pingCount == 1)
  #expect(await state.closeFrames == [WebSocketCloseFrame(code: .goingAway, reason: Data("bye".utf8))])
}

@Test func webSocketConnectionMessagesStreamReceivesUntilClose() async throws {
  let state = QueuedSocketState(incomingMessages: [
    .text("first"),
    .data(Data("second".utf8))
  ])
  let client = WebSocketClient.live(transport: QueuedWebSocketTransport(state: state))
  let connection = try await client.connect(
    WebSocketRequest(url: URL(string: "wss://example.com/socket")!)
  )
  var iterator = connection.messages().makeAsyncIterator()

  let first = try await iterator.next()
  let second = try await iterator.next()

  #expect(first == .text("first"))
  #expect(second == .data(Data("second".utf8)))

  do {
    _ = try await iterator.next()
    Issue.record("Expected the stream to finish by throwing the close error.")
  } catch let error as NetworkError {
    #expect(error.statusCode == nil)
    guard case .webSocketClosed(let code, let reason) = error else {
      Issue.record("Expected a WebSocket close error.")
      return
    }
    #expect(code == .normalClosure)
    #expect(String(data: reason ?? Data(), encoding: .utf8) == "done")
  }
}

@Test func webSocketSessionReconnectsAndEmitsLifecycleEvents() async throws {
  let state = ReconnectingSocketState()
  let client = WebSocketClient.live(transport: ReconnectingWebSocketTransport(state: state))
  let session = client.session(
    for: WebSocketRequest(url: URL(string: "wss://example.com/socket")!),
    configuration: WebSocketSessionConfiguration(
      maximumReconnectAttempts: 1,
      reconnectDelay: { _ in .zero },
      sleep: { _ in }
    )
  )
  var iterator = session.events().makeAsyncIterator()

  guard case .connected(let subprotocol)? = try await iterator.next() else {
    Issue.record("Expected the session to connect.")
    return
  }
  #expect(subprotocol == "comet-demo")

  guard case .message(.text("first"))? = try await iterator.next() else {
    Issue.record("Expected the first message.")
    return
  }

  guard case .disconnected(let error)? = try await iterator.next() else {
    Issue.record("Expected a disconnect after the first mocked session closes.")
    return
  }
  guard case .webSocketClosed(let code, _) = error else {
    Issue.record("Expected a WebSocket close error.")
    return
  }
  #expect(code == .normalClosure)

  guard case .reconnecting(let attempt, let delay)? = try await iterator.next() else {
    Issue.record("Expected a reconnect event.")
    return
  }
  #expect(attempt == 1)
  #expect(delay == .zero)

  guard case .connected? = try await iterator.next() else {
    Issue.record("Expected the session to reconnect.")
    return
  }
  guard case .message(.text("second"))? = try await iterator.next() else {
    Issue.record("Expected the second message.")
    return
  }

  #expect(await state.connectCount() == 2)
}

@Test func webSocketSessionCloseDuringReconnectDelayStopsEventStream() async throws {
  let state = ReconnectingSocketState()
  let sleepGate = SleepGate()
  let client = WebSocketClient.live(transport: ReconnectingWebSocketTransport(state: state))
  let session = client.session(
    for: WebSocketRequest(url: URL(string: "wss://example.com/socket")!),
    configuration: WebSocketSessionConfiguration(
      maximumReconnectAttempts: 1,
      reconnectDelay: { _ in .seconds(1) },
      sleep: { _ in await sleepGate.sleep() }
    )
  )
  var iterator = session.events().makeAsyncIterator()

  guard case .connected? = try await iterator.next() else {
    Issue.record("Expected the session to connect.")
    return
  }
  guard case .message(.text("first"))? = try await iterator.next() else {
    Issue.record("Expected the first message.")
    return
  }
  guard case .disconnected? = try await iterator.next() else {
    Issue.record("Expected a disconnect after the first mocked session closes.")
    return
  }
  guard case .reconnecting? = try await iterator.next() else {
    Issue.record("Expected the session to wait before reconnecting.")
    return
  }

  try await session.close()
  await sleepGate.resumeAll()

  let next = try await iterator.next()
  #expect(next == nil)
  #expect(await state.connectCount() == 1)
}

@Test func webSocketSessionSendsThroughCurrentConnection() async throws {
  let state = TestSocketState()
  let client = WebSocketClient.live(transport: TestWebSocketTransport(state: state))
  let session = client.session(
    for: WebSocketRequest(url: URL(string: "wss://example.com/socket")!)
  )

  try await session.send(.text("hello"))

  #expect(await state.sentMessages == [.text("hello")])
}

@Test func networkErrorSummarizesWebSocketCloseReason() {
  let error = NetworkError.webSocketClosed(
    code: .normalClosure,
    reason: Data("Finished".utf8)
  )

  #expect(error.debugSummary == "WebSocket closed (1000): Finished")
}
