# WebSocket Sessions

Use ``WebSocketClient`` for realtime connections through the same transport-oriented style as HTTP requests.

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

Use `MockWebSocketTransport` in tests and demos when you need deterministic socket behavior.

```swift
let sockets = WebSocketClient.live(
  transport: MockWebSocketTransport(
    selectedSubprotocol: "comet.demo.v1",
    echoSentMessages: true
  )
)
```

The current WebSocket layer is intentionally low-level. Resilient sessions, reconnect policies, and `AsyncSequence` message consumption are planned for the next larger feature pass.
