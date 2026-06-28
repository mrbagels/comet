<p align="center">
  <img src="Resources/Brand/icon-gradient.svg" alt="Comet logo" width="112">
</p>

<h1 align="center">Comet</h1>

<p align="center">
  <strong>Typed networking for Apple-platform Swift apps.</strong>
</p>

<p align="center">
  <a href="https://github.com/mrbagels/comet/actions/workflows/ci.yml"><img src="https://github.com/mrbagels/comet/actions/workflows/ci.yml/badge.svg?branch=next" alt="CI"></a>
  <a href="https://github.com/mrbagels/comet/releases"><img src="https://img.shields.io/github/v/release/mrbagels/comet?sort=semver" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/platforms-iOS%2018%2B%20%7C%20macOS%2015%2B%20%7C%20visionOS%202%2B-blue" alt="Supported platforms">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/mrbagels/comet" alt="License"></a>
</p>

Comet turns API endpoints into Swift types. It ships with a `URLSession`-backed live client, middleware for production behavior, opt-in response caching, deterministic testing transports, cassette recording and replay, request activity and trace streams, response streaming, transfer progress hooks, and resilient WebSocket sessions.

The latest published release is `0.2.0`, the completed V2 foundation. The `next` branch is carrying the `0.2.x` patch train toward `0.3.0`, including cache, trace, contract-testing, generated-client, and server-direction work.

## At A Glance

| Surface | What It Provides |
| --- | --- |
| `Comet` | Typed HTTP requests, WebSocket sessions, serializers, middleware, retry, cache, deduplication, activity events, traces, streaming, and progress primitives |
| `CometTesting` | Mock transports, cassette recording, replay transports, and mock WebSocket sessions |
| `CometTCA` | Lightweight Composable Architecture helpers for request effects |
| `CometPlayground` | iPhone-first verification app for HTTP, replay, activity, and realtime flows |

## Toolchain And Platforms

- Swift 6.2
- iOS 18+
- macOS 15+
- visionOS 2+

The shipped live HTTP and WebSocket transports are `URLSession`-backed. Server-side Swift support is possible through the transport protocols, but a server live transport is not included today.

## Install

```swift
.package(url: "https://github.com/mrbagels/comet.git", from: "0.2.0")
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

For refresh and 401 replay, configure the auth coordinator once:

```swift
let auth = AuthenticationCoordinator.bearer(
  token: { await authStore.accessToken },
  refresh: { try await authStore.refreshAccessToken() }
)

let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [AuthenticationMiddleware(coordinator: auth)]
  ),
  transport: URLSessionTransport()
)
```

### Retries, Metadata, And Activity

```swift
import Comet

let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      TracePropagationMiddleware(),
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

Requests can carry metadata into logs and activity events. Retry behavior is conservative by default: `RetryMiddleware` retries safe methods such as `GET` automatically, while write requests need an idempotency key or an explicit retry policy.

```swift
var options: RequestOptions {
  .init(
    idempotencyKey: "create-user-\(draft.id)",
    metadata: RequestMetadata(name: "CreateUser", tags: ["users"]),
    statusValidation: .successOrNotModified
  )
}
```

Activity events also expose diagnostic helpers for UI and logging code:

```swift
for await event in client.activity {
  print(event.kind)
  print(event.diagnosticSummary)
}
```

### Trace Propagation

`TracePropagationMiddleware` writes the W3C `traceparent` header and completed `RequestTrace` values expose the propagated trace ID.

```swift
let context = TraceContext(
  traceID: "4bf92f3577b34da6a3ce929d0e0e4736",
  parentID: "00f067aa0ba902b7",
  flags: "01"
)!

var options: RequestOptions {
  .init(
    metadata: RequestMetadata(
      name: "GetUser",
      operationID: "users.get",
      traceContext: context
    )
  )
}

for await trace in client.traces {
  print(trace.traceID as Any)
}
```

### Opt-In Response Cache

```swift
let cache = MemoryHTTPCacheStore()

let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      CacheMiddleware(store: cache)
    ]
  ),
  transport: URLSessionTransport()
)

var options: RequestOptions {
  RequestOptions(cachePolicy: .returnCacheElseLoad)
}
```

Use `FileHTTPCacheStore` when responses should survive process restarts:

```swift
let cache = FileHTTPCacheStore(
  namespace: "api-v1",
  maximumSizeBytes: 25 * 1024 * 1024
)
```

`returnCacheElseLoad` serves fresh cached responses and revalidates stale entries
when `ETag` or `Last-Modified` validators are available. Use `.revalidate` to
force a conditional request, `.cacheOnly` for offline reads, `.networkOnly` to
avoid reading or writing the cache, or `.reloadIgnoringCache` to fetch and store
a replacement.

For offline-tolerant reads, opt in to stale fallback when the network request
fails:

```swift
RequestOptions(
  cachePolicy: HTTPCachePolicy(
    strategy: .returnCacheElseLoad,
    allowsStaleIfError: true
  )
)
```

Cache decisions are included in completed traces:

```swift
for await trace in client.traces {
  print(trace.cacheEvents.map(\.kind))
}
```

### Query Items

`QueryItem` includes helpers for common optional, boolean, collection, joined, and date parameters.

```swift
var queryItems: [QueryItem] {
  QueryItems {
    QueryItem("search", searchTerm)
    QueryItem.optional("limit", limit)
    QueryItem.bool("includeArchived", includeArchived)
    QueryItem.items("tag", values: tags)
    QueryItem.joined("ids", values: selectedIDs)
    QueryItem.date("createdAfter", cutoffDate, style: .iso8601)
  }
}
```

### Typed API Errors

Requests can opt into decoding structured HTTP error bodies while preserving the raw `NetworkError.http` information.

```swift
struct APIError: Decodable, Sendable {
  let code: String
  let message: String
}

struct CreateUser: APIRequestWithErrorResponse {
  typealias Response = User
  typealias ErrorResponse = APIError

  let path: Path = "users"
  let method: HTTPMethod = .post
  let responseSerializer: ResponseSerializer<User> = .json(User.self)
  let errorResponseSerializer: ErrorResponseSerializer<APIError> = .json(APIError.self)
}

do {
  let user = try await client.sendWithTypedErrors(CreateUser())
} catch let error as APIClientError<APIError> {
  print(error.decodedErrorBody?.message ?? error.networkError.debugSummary)
}
```

### cURL Output

Prepared requests can produce shell-safe cURL output. Use `HTTPClient.prepare(_:)` when you want to inspect the exact transport-ready request before sending it. Multiline is the default for logs, while compact output is useful for copying into single-line fields. JSON request bodies can also be pretty-printed when multiline readability matters.

```swift
let preparedRequest = try client.prepare(CreateTodoRequest())
let curl = preparedRequest.curlCommand(style: .compact)

let readableCurl = preparedRequest.curlCommand(
  options: CURLCommandOptions(
    style: .multiline,
    bodyFormatting: .prettyPrintedJSON
  )
)
```

Verbose request logging uses the same options:

```swift
LoggingMiddleware(
  logLevel: .verbose,
  curlCommandOptions: CURLCommandOptions(style: .compact)
)
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

For long-lived readers, use the message stream and stop iterating when the connection
closes or the surrounding task is cancelled:

```swift
for try await message in connection.messages() {
  // Handle .text or .data frames.
}
```

For lifecycle events and bounded reconnect attempts, use a session:

```swift
let session = sockets.session(
  for: WebSocketRequest(url: URL(string: "wss://ws.postman-echo.com/raw")!),
  configuration: WebSocketSessionConfiguration(maximumReconnectAttempts: 3)
)

for try await event in session.events() {
  // Handle .connected, .message, .disconnected, and .reconnecting.
}
```

### Streaming And Progress

```swift
for try await line in client.lines(StreamEvents()) {
  print(line)
}

for try await event in client.serverSentEvents(StreamEvents()) {
  print(event.data)
}

let response = try await client.sendRaw(UploadAsset()) { progress in
  print(progress.kind, progress.completedBytes, progress.totalBytes as Any)
}
```

### Deterministic Testing And Replay

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

`MockTransport` is the fastest path for fully in-memory tests. `RecordingTransport` and `ReplayTransport` are for higher-fidelity fixture workflows when you want to capture live traffic once and replay it deterministically later.

Recorded cassettes can include URLs, headers, request bodies, response bodies, cookies, and authorization data. `RecordingTransport` redacts common sensitive headers by default and supports custom request and response body redaction. Review generated fixtures before committing them.

```swift
let recorder = RecordingTransport(
  base: URLSessionTransport(),
  redaction: RecordingRedaction(
    redactRequestBody: { request in request.url.path.contains("sessions") },
    redactResponseBody: { response in response.headers[.contentType] == "application/json" }
  )
)
```

`RecordingRedaction` is an alias for Comet's shared `RedactionPolicy`, so the same policy shape can be used for cassettes, logging, and cURL output.

## Example App

`Examples/CometPlayground` is an iPhone-first verification app generated with XcodeGen. It provides:

- a focused smoke test target: `CometPlaygroundTests`
- deterministic mock verification with `CometTesting.MockTransport`
- deterministic socket verification with `CometTesting.MockWebSocketTransport`
- live transport checks through `URLSessionTransport` and `URLSessionWebSocketTransport`
- proof, structured activity, failure-gallery, request-inspector, and detail flows showing which APIs are exercised and what output to verify

The full walkthrough lives in [Examples/CometPlayground/README.md](Examples/CometPlayground/README.md).

## Documentation

The DocC catalog includes workflow articles for authenticated JSON requests, retries and activity, request tracing, streaming and progress, typed API errors, testing and cassettes, WebSockets, and TCA integration.

## Verification

Run the package tests:

```sh
swift test --disable-xctest
```

Generate the example Xcode project:

```sh
cd Examples/CometPlayground
xcodegen generate
```

Run the example smoke tests:

```sh
xcodebuild test -project CometPlayground.xcodeproj -scheme CometPlaygroundApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' SWIFT_ENABLE_EXPLICIT_MODULES=NO
```

GitHub Actions runs the Swift package suite, secret scanning, public API break gating, and the iOS example smoke tests on every push to `next` and `master`.

Check for public API changes against the latest patch release:

```sh
swift package diagnose-api-breaking-changes v0.2.0
```

Run a fresh external client smoke check:

```sh
.github/scripts/fresh-client-smoke.sh
```

## Branching

- `next` is the default integration branch for upcoming work.
- `master` is the stable release branch.
- Short-lived `feat/`, `fix/`, `refactor/`, `docs/`, `chore/`, `spike/`, and `hotfix/` branches should branch from `next`.
- Normal work merges back into `next`, and releases promote from `master`.

## Brand Assets

SVG brand assets live in [Resources/Brand](Resources/Brand). The README uses the gradient icon directly from that folder, and the playground app bundles the same mark through its asset catalog and app icon set.

## Repository Layout

- `Sources/`: package source targets
- `Tests/`: package test targets
- `Examples/CometPlayground/`: XcodeGen-driven iOS demo app
- `Resources/Brand/`: SVG logo and icon files for docs, README, and app assets
- `.github/scripts/fresh-client-smoke.sh`: external package integration smoke check
- `.github/workflows/ci.yml`: package and iOS smoke test automation
- `docs/ARCHITECTURE.md`: architecture notes
- `docs/IMPLEMENTATION_PLAN.md`: implementation plan and rollout notes
- `docs/PRODUCT_ROADMAP.md`: product roadmap and feature planning
- `docs/RELEASE_PLAN_0_3.md`: patch-release plan from `0.2.x` to `0.3.0`

## What To Open First

If you want to understand or modify the current core flows, start here:

- [Sources/Comet/Core/HTTPClient.swift](Sources/Comet/Core/HTTPClient.swift)
- [Sources/Comet/WebSockets/WebSocketTypes.swift](Sources/Comet/WebSockets/WebSocketTypes.swift)
- [Sources/CometTesting/MockWebSocketTransport.swift](Sources/CometTesting/MockWebSocketTransport.swift)
- [Sources/CometTesting/RecordingTransport.swift](Sources/CometTesting/RecordingTransport.swift)
- [Examples/CometPlayground/App/DemoCatalog.swift](Examples/CometPlayground/App/DemoCatalog.swift)
- [Examples/CometPlayground/App/HomeTab.swift](Examples/CometPlayground/App/HomeTab.swift)
- [Examples/CometPlayground/App/ActivityTab.swift](Examples/CometPlayground/App/ActivityTab.swift)
- [Examples/CometPlayground/project.yml](Examples/CometPlayground/project.yml)
