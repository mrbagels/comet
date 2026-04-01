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

@Test func networkErrorSummarizesWebSocketCloseReason() {
  let error = NetworkError.webSocketClosed(
    code: .normalClosure,
    reason: Data("Finished".utf8)
  )

  #expect(error.debugSummary == "WebSocket closed (1000): Finished")
}
