# Comet

Comet is a modern Swift networking library for Apple-platform apps today. It ships with a `URLSession`-backed live transport and a transport seam that also supports mocks, recorders, replayers, and future non-`URLSession` transports.

## Package Products

- `Comet`: typed HTTP requests, WebSocket connections, middleware, retry, deduplication, and activity events
- `CometTesting`: mocks, recorders, JSON cassettes, replay transports, and mock WebSocket sessions
- `CometTCA`: lightweight Composable Architecture integration

## Toolchain And Platforms

- Swift 6.2
- iOS 18+
- macOS 15+
- visionOS 2+

The live HTTP and WebSocket transports are `URLSession`-backed. Server-side Swift support is possible through the transport protocols, but a server live transport is not included today.

## Platform Status

Comet’s shipped live transports are `URLSessionTransport` and `URLSessionWebSocketTransport`, so the production-ready story today is Apple-platform client apps. The core abstractions are intentionally transport-replaceable, but a server-side live transport does not ship yet.

## Install

```swift
.package(url: "https://github.com/mrbagels/comet.git", from: "0.1.1")
```

Import the target you need:

```swift
import Comet
import CometTesting
```

## Quick Start

### Authenticated JSON

```swift
import Comet
import HTTPTypes

struct User: Decodable, Sendable {
  let id: Int
  let name: String
}

struct GetUser: APIRequest {
  let userID: Int

  var path: Path { "users" / self.userID }
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<User> = .json(User.self)

  // API versioning is opt-in. Add it only when your server expects it.
  var options: RequestOptions {
    .init(apiVersion: "v1")
  }
}

let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      BearerTokenMiddleware {
        await authStore.accessToken
      }
    ]
  ),
  transport: URLSessionTransport()
)

let user = try await client.send(GetUser(userID: 42))
```

### Plain Text And Raw HTTP

```swift
import Comet
import HTTPTypes

struct ExampleDomainRequest: APIRequest {
  let path: Path = "ignored"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()

  var options: RequestOptions {
    .init(absoluteURL: URL(string: "https://example.com")!)
  }
}

let client = HTTPClient.live(
  configuration: .default(baseURL: URL(string: "https://placeholder.invalid")!),
  transport: URLSessionTransport()
)

let html = try await client.send(ExampleDomainRequest())
let raw = try await client.sendRaw(ExampleDomainRequest())
```

### Retries, Logging, And Activity

```swift
import Comet

let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      RetryMiddleware(maxAttempts: 3),
      LoggingMiddleware(logLevel: .verbose)
    ]
  ),
  transport: URLSessionTransport()
)

Task {
  for await event in client.activity {
    print(event)
  }
}
```

Requests can carry metadata into logs and activity events, and retry behavior is conservative by default. `RetryMiddleware` retries safe methods such as `GET` automatically, while write requests need an idempotency key or an explicit retry policy.

```swift
var options: RequestOptions {
  .init(
    idempotencyKey: "create-user-\(draft.id)",
    metadata: RequestMetadata(name: "CreateUser", tags: ["users"]),
    statusValidation: .successOrNotModified
  )
}
```

### WebSocket Sessions

```swift
import Comet

let sockets = WebSocketClient.live(
  transport: URLSessionWebSocketTransport()
)

let connection = try await sockets.connect(
  WebSocketRequest(
    url: URL(string: "wss://ws.postman-echo.com/raw")!,
    timeout: .seconds(10)
  )
)

try await connection.send(.text(#"{"kind":"echo","library":"Comet"}"#))
let reply = try await connection.receive()
try await connection.close(code: .normalClosure)
```

### Deterministic Testing And Replay Fixtures

```swift
import Comet
import CometTesting

let recorder = RecordingTransport(base: URLSessionTransport())
let liveClient = HTTPClient.live(
  configuration: .default(baseURL: URL(string: "https://api.example.com")!),
  transport: recorder
)

_ = try await liveClient.send(GetUser(userID: 42))

let cassetteURL = URL(fileURLWithPath: "Tests/Fixtures/get-user-42.json")
let cassette = await recorder.cassette()
try cassette.write(to: cassetteURL)

let replay = try ReplayTransport(contentsOf: cassetteURL)
let replayClient = HTTPClient.live(
  configuration: .default(baseURL: URL(string: "https://api.example.com")!),
  transport: replay
)

let recordedUser = try await replayClient.send(GetUser(userID: 42))
```

`MockTransport` is still the fastest path for fully in-memory tests. `RecordingTransport` and `ReplayTransport` are for higher-fidelity fixture workflows when you want to capture live traffic once and replay it deterministically later.

Recorded cassettes can include URLs, headers, request bodies, response bodies, cookies, and authorization data. `RecordingTransport` redacts common sensitive headers by default and supports custom request/response body redaction. Review generated fixtures before committing them.

```swift
let recorder = RecordingTransport(
  base: URLSessionTransport(),
  redaction: RecordingRedaction(
    redactRequestBody: { request in request.url.path.contains("sessions") },
    redactResponseBody: { response in response.headers[.contentType] == "application/json" }
  )
)
```

`RecordingRedaction` is an alias for Comet’s shared `RedactionPolicy`, so the same policy shape can be used for cassettes, logging, and cURL output.

For realtime tests, `MockWebSocketTransport` gives you the same deterministic control for handshake, echo, queued inbound messages, ping tracking, and close frames.

## Verification

Run the package tests:

```sh
swift test
```

Generate the example Xcode project:

```sh
cd Examples/CometPlayground
xcodegen generate
```

Run the example smoke tests from the command line:

```sh
xcodebuild test -project CometPlayground.xcodeproj -scheme CometPlaygroundApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'
```

GitHub Actions runs both the Swift package suite and the iOS example smoke tests on every push to `next` and `master`.

Check for public API changes against the latest release tag:

```sh
swift package diagnose-api-breaking-changes v0.1.0
```

The `0.1.x` line is the public-prep patch line. The broader structure and API refactor will continue through patch releases until the completed v2 foundation becomes `0.2.0`.

## Branching

This repo now follows the shared package branch model:

- `next` is the default integration branch for upcoming work
- `master` is the stable release branch
- short-lived `feat/`, `fix/`, `refactor/`, `docs/`, `chore/`, `spike/`, and `hotfix/` branches should branch from `next`
- normal work merges back into `next`, and releases promote from `master`

## Repository Layout

- `Sources/`: package source targets
- `Tests/`: package test targets
- `Examples/CometPlayground/`: XcodeGen-driven iOS demo app
- `.github/workflows/ci.yml`: package and iOS smoke test automation
- `docs/ARCHITECTURE.md`: architecture notes
- `docs/IMPLEMENTATION_PLAN.md`: implementation plan and rollout notes

## Example App

The example project is an iPhone-first verification app for the package. It gives you:

- an iOS app target: `CometPlaygroundApp`
- a focused smoke test target: `CometPlaygroundTests`
- deterministic mock verification with `CometTesting.MockTransport`
- deterministic socket verification with `CometTesting.MockWebSocketTransport`
- live transport checks through `URLSessionTransport` and `URLSessionWebSocketTransport`
- focused proof, activity, and detail flows showing which APIs are being exercised and what output to verify

The full walkthrough lives in [Examples/CometPlayground/README.md](Examples/CometPlayground/README.md).

## What To Open First

If you want to understand or modify the example apps, start here:

- [Sources/Comet/WebSockets/WebSocketTypes.swift](Sources/Comet/WebSockets/WebSocketTypes.swift)
- [Sources/Comet/WebSockets/URLSessionWebSocketTransport.swift](Sources/Comet/WebSockets/URLSessionWebSocketTransport.swift)
- [Sources/CometTesting/MockWebSocketTransport.swift](Sources/CometTesting/MockWebSocketTransport.swift)
- [DemoCatalog.swift](Examples/CometPlayground/App/DemoCatalog.swift)
- [RootView.swift](Examples/CometPlayground/App/RootView.swift)
- [HomeTab.swift](Examples/CometPlayground/App/HomeTab.swift)
- [ProofsTab.swift](Examples/CometPlayground/App/ProofsTab.swift)
- [ActivityTab.swift](Examples/CometPlayground/App/ActivityTab.swift)
- [DemoDetailScreen.swift](Examples/CometPlayground/App/DemoDetailScreen.swift)
- [DemoRequests.swift](Examples/CometPlayground/App/DemoRequests.swift)
- [DemoClientFactory.swift](Examples/CometPlayground/App/DemoClientFactory.swift)
- [PlaygroundStyle.swift](Examples/CometPlayground/App/PlaygroundStyle.swift)
- [project.yml](Examples/CometPlayground/project.yml)
