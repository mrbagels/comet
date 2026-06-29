# WebSocket Sessions

Use ``WebSocketClient`` for realtime connections through the same transport-oriented style as HTTP requests.

``URLSessionWebSocketTransport`` uses `URLSessionWebSocketTask` and is available only on Apple platforms. Server-side Swift apps can keep the same ``WebSocketClient`` and ``WebSocketTransport`` surface by providing a custom transport.

## Connect

```swift
let sockets = WebSocketClient.live(
  transport: URLSessionWebSocketTransport()
)

let connection = try await sockets.connect(
  WebSocketRequest(
    url: URL(string: "wss://ws.postman-echo.com/raw")!,
    timeout: .seconds(10)
  )
)
```

## Send And Receive

```swift
try await connection.send(.text(#"{"kind":"echo","library":"Comet"}"#))
let message = try await connection.receive()
try await connection.close(code: .normalClosure)
```

Use ``WebSocketConnection/messages()`` when a reader should consume frames until the
connection closes or the task is cancelled.

```swift
for try await message in connection.messages() {
  // Route text and binary frames from a single async loop.
}
```

Use ``WebSocketSession`` when the app wants lifecycle events and bounded reconnect attempts over the low-level connection.

```swift
let session = sockets.session(
  for: WebSocketRequest(url: URL(string: "wss://ws.postman-echo.com/raw")!),
  configuration: WebSocketSessionConfiguration(maximumReconnectAttempts: 3)
)

for try await event in session.events() {
  switch event {
  case .connected:
    break
  case .message(let message):
    print(message)
  case .disconnected(let error):
    print(error.debugSummary)
  case .reconnecting(let attempt, let delay):
    print("reconnect", attempt, delay)
  }
}
```

Use `MockWebSocketTransport` in tests and demos when you need deterministic socket behavior.

```swift
let sockets = WebSocketClient.live(
  transport: MockWebSocketTransport(
    selectedSubprotocol: "comet.demo.v1",
    echoSentMessages: true
  )
)
```
