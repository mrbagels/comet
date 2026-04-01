import Foundation
import Testing
import Comet
import CometTesting

@Test func mockWebSocketTransportEchoesSentMessagesAndTracksSessionActivity() async throws {
  let transport = MockWebSocketTransport(
    selectedSubprotocol: "comet-demo",
    echoSentMessages: true
  )

  let connection = try await transport.connect(
    WebSocketRequest(url: URL(string: "wss://example.com/socket")!)
  )

  #expect(connection.selectedSubprotocol == "comet-demo")

  try await connection.send(.text("hello"))
  try await connection.ping()
  let response = try await connection.receive()
  try await connection.close(code: .normalClosure, reason: Data("done".utf8))

  #expect(response == .text("hello"))
  #expect(await transport.sentMessages() == [.text("hello")])
  #expect(await transport.pingCount() == 1)
  #expect(await transport.closeFrames() == [WebSocketCloseFrame(code: .normalClosure, reason: Data("done".utf8))])
  #expect(await transport.connectRequests().first?.url.absoluteString == "wss://example.com/socket")
}

@Test func mockWebSocketTransportCanQueueIncomingMessages() async throws {
  let transport = MockWebSocketTransport(incomingMessages: [.text("first")])
  let connection = try await transport.connect(
    WebSocketRequest(url: URL(string: "wss://example.com/socket")!)
  )

  await transport.enqueueIncoming(.text("second"))

  let first = try await connection.receive()
  let second = try await connection.receive()

  #expect(first == .text("first"))
  #expect(second == .text("second"))
}

@Test func mockWebSocketTransportThrowsAfterClose() async throws {
  let transport = MockWebSocketTransport()
  let connection = try await transport.connect(
    WebSocketRequest(url: URL(string: "wss://example.com/socket")!)
  )

  try await connection.close(code: .goingAway)

  await #expect(throws: NetworkError.self) {
    _ = try await connection.receive()
  }
}
