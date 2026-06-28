# Comet Architecture

> Swift 6.2+ · iOS 18+ today · shipped live transports: `URLSession` HTTP and WebSocket · server-side transport is future work

This document reflects the current implemented architecture of Comet.

---

## Philosophy

Comet is meant to be a long-lived networking foundation:

- keep the core small
- keep the public model transport-aware but not `URLSession`-shaped
- make request construction safe and ergonomic
- make behavior deterministic through dependency injection
- preserve real HTTP concepts instead of over-fitting to JSON-only APIs
- make testing a first-class workflow

The current implementation leans on these principles:

- `HTTPClient` is the public execution boundary.
- `HTTPTransport` is the transport seam.
- middleware is the main extension point for auth, retry, and logging.
- `HTTPBody` and `ResponseSerializer` keep the library format-agnostic.
- `RequestOptions` collects opt-in behavior instead of growing `APIRequest`.

---

## Package Structure

```text
comet/
├── Package.swift
├── Sources/
│   ├── Comet/
│   ├── CometTCA/
│   └── CometTesting/
├── Tests/
│   ├── CometTests/
│   ├── CometTCATests/
│   └── CometTestingTests/
├── Examples/
│   └── CometPlayground/
├── Resources/
│   └── Brand/
└── docs/
    ├── ARCHITECTURE.md
    ├── IMPLEMENTATION_PLAN.md
    └── PRODUCT_ROADMAP.md
```

### Products

- `Comet`
- `CometTCA`
- `CometTesting`

### Dependencies

```text
Comet
└── swift-http-types

CometTCA
├── Comet
├── swift-dependencies
└── swift-composable-architecture

CometTesting
├── Comet
└── swift-http-types
```

### Why This Split

- `Comet` owns request modeling, execution, middleware, and observability.
- `CometTCA` owns dependency wiring and effect helpers.
- `CometTesting` keeps mocks and recorders out of the production surface.
- `Examples/CometPlayground` is a generated iOS proof-of-concept app, not part of the library package itself.
- `Resources/Brand` stores first-party SVG assets used by docs, README, and the playground app asset catalog.

---

## V1 Scope

The current MVP includes:

- `HTTPClient`
- `HTTPTransport`
- `URLSessionTransport`
- `WebSocketClient`
- `WebSocketTransport`
- `URLSessionWebSocketTransport`
- `APIRequest`
- `Path`
- `HTTPBody`
- `ResponseSerializer`
- `RawResponse`
- `EmptyResponse`
- `StatusValidation`
- `RequestOptions`
- `RequestBuilder`
- `NetworkError`
- middleware
- retry support
- runtime logging
- in-flight deduplication
- activity events
- `CometTCA`
- `CometTesting`
- XcodeGen playground app

Deferred for later:

- stale-while-revalidate
- batch requests
- higher-level TCA domain helpers beyond generic request state
- a server-specific live transport

---

## Source Layout

```text
Sources/Comet/
├── Core/
│   ├── ClientConfiguration.swift
│   ├── HTTPClient.swift
│   ├── HTTPFields+Utilities.swift
│   ├── HTTPTransport.swift
│   ├── PreparedRequest.swift
│   ├── RequestBuilder.swift
│   └── URLSessionTransport.swift
├── WebSockets/
│   ├── URLSessionWebSocketTransport.swift
│   └── WebSocketTypes.swift
├── Debug/
│   └── CURLCommand.swift
├── Deduplication/
│   └── RequestDeduplicator.swift
├── Diagnostics/
│   ├── RedactionPolicy.swift
│   └── RequestMetadata.swift
├── Errors/
│   └── NetworkError.swift
├── Middleware/
│   ├── BearerTokenMiddleware.swift
│   ├── LoggingMiddleware.swift
│   ├── Middleware.swift
│   ├── MiddlewareChain.swift
│   ├── RequestRetryPolicy.swift
│   └── RetryMiddleware.swift
├── Observability/
│   ├── EventBroadcaster.swift
│   └── NetworkEvent.swift
├── Protocols/
│   └── APIRequest.swift
└── Types/
    ├── Builders/
    │   ├── HTTPFieldsBuilder.swift
    │   └── QueryItemsBuilder.swift
    ├── EmptyResponse.swift
    ├── HTTPBody.swift
    ├── HTTPMethod.swift
    ├── Path.swift
    ├── QueryItem.swift
    ├── RawResponse.swift
    ├── RequestOptions.swift
    ├── ResponseSerializer.swift
    └── StatusValidation.swift

Sources/CometTCA/
├── Effect+Request.swift
└── HTTPClient+Dependency.swift

Sources/CometTesting/
├── Cassette.swift
├── HTTPClient+Testing.swift
├── MockWebSocketTransport.swift
├── MockTransport.swift
├── RecordingRedaction.swift
└── RecordingTransport.swift
```

---

## Execution Flow

```text
APIRequest
  → RequestBuilder
  → PreparedRequest
  → optional deduplication
  → MiddlewareChain.prepare
  → HTTPTransport
  → MiddlewareChain.process(result:)
  → RawResponse
  → status validation
  → ResponseSerializer<Response>
  → typed Response

WebSocketRequest
  → WebSocketTransport.connect
  → WebSocketConnection
  → send / receive / ping / close
```

### Important Boundary Decisions

- `sendRaw` returns the transport result after middleware but before status validation and decoding.
- `send` applies `RequestOptions.statusValidation` and then runs the serializer.
- activity events describe the underlying request lifecycle, including retries.
- deduplication is opt-in through `RequestOptions.deduplicationKey`.
- WebSocket sessions use a dedicated `WebSocketClient` surface instead of forcing socket behavior through `APIRequest`.

---

## Core Contracts

### `APIRequest`

```swift
public protocol APIRequest: Sendable {
    associatedtype Response: Sendable

    var path: Path { get }
    var method: HTTPMethod { get }
    var headers: HTTPFields { get }
    var queryItems: [QueryItem] { get }
    var body: HTTPBody { get }
    var options: RequestOptions { get }
    var responseSerializer: ResponseSerializer<Response> { get }
}
```

Defaults exist for `headers`, `queryItems`, `body`, and `options`.

### `Path`

`Path` is the safe route builder used by requests:

- normalizes slash handling
- percent-encodes individual segments
- supports ergonomic segment composition with `/`

### `QueryItem`

`QueryItem` represents URL query parameters and includes helpers for common request definitions:

- optional values
- boolean values
- repeated items from collections
- joined collection values
- ISO 8601, epoch seconds, and epoch milliseconds date encodings

`QueryItemsBuilder` accepts individual items, optional items, arrays, and arrays of optional items.

### `RequestOptions`

`RequestOptions` is the main opt-in extension surface:

- `apiVersion`
- `absoluteURL`
- `timeout`
- `idempotencyKey`
- `deduplicationKey`
- `metadata`
- `statusValidation`
- `redactionPolicy`
- `retryPolicy`
- request-level middleware

`statusValidation` defaults to `.successCodes`.
Request metadata flows into activity events and logs. Request redaction and retry policy override shared defaults only when supplied.

### `HTTPBody`

`HTTPBody` is a deferred body description that resolves using `ClientConfiguration`.

Current factories:

- `.none`
- `.data`
- `.text`
- `.json`
- `.formURLEncoded`

Important behavior:

- body-level headers are returned together with the body bytes
- `.text` throws a typed encoding error if the requested string encoding fails
- `.json` uses the encoder factory from configuration unless overridden

### `ResponseSerializer`

Current serializers:

- `.json`
- `.data`
- `.string`
- `.empty`
- `.custom`

This keeps the client core format-agnostic while still making JSON ergonomic.

### `ErrorResponseSerializer`

`ErrorResponseSerializer<ErrorResponse>` mirrors `ResponseSerializer` for unsuccessful HTTP responses. It decodes typed domain errors while preserving the raw `NetworkError.http` details inside `APIClientError`.

Typed error decoding is opt-in through either:

- `HTTPClient.send(_:errorResponseSerializer:)`
- `APIRequestWithErrorResponse` plus `HTTPClient.sendWithTypedErrors(_:)`

The default `HTTPClient.send(_:)` path continues to throw `NetworkError`.

### `RawResponse`

`RawResponse` carries:

- raw body bytes
- numeric status code
- HTTP headers

It is the transport-facing response model for middleware, raw request flows, and custom serializers.

### `StatusValidation`

`StatusValidation` controls what `send` treats as success:

- `.successCodes`
- `.exact`
- `.range`
- `.custom`
- `.successOrNotModified`
- `.successAndRedirects`
- `.noContent`

Use `sendRaw` when the caller wants to handle all statuses manually.

---

## Configuration

### `ClientConfiguration`

`ClientConfiguration` currently owns:

- `baseURL`
- `defaultHeaders`
- default timeout
- global middleware
- JSON encoder/decoder factories
- time source
- sleep function
- request ID factory
- retry randomness source

### JSON Defaults

Comet no longer hard-wires snake_case JSON behavior into the default configuration.

Current options:

- `ClientConfiguration.default(baseURL:)` uses standard `JSONEncoder` / `JSONDecoder`
- `ClientConfiguration.default(baseURL:jsonPreset:)` supports `.standard` and `.snakeCaseISO8601`
- helper factories exist for both standard and snake_case JSON coders

This keeps the default less surprising while still making common API conventions easy to opt into.

---

## Transport Layer

### `HTTPTransport`

```swift
public protocol HTTPTransport: Sendable {
    func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse
}
```

### `URLSessionTransport`

`URLSessionTransport` is the shipped live transport for app-side usage.

Responsibilities:

- adapt `PreparedRequest` into `URLRequest`
- execute with `URLSession`
- map transport failures into `NetworkError`
- return `RawResponse`

### `WebSocketTransport`

```swift
public protocol WebSocketTransport: Sendable {
    func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection
}
```

`WebSocketClient` mirrors the role `HTTPClient` plays for HTTP requests, but keeps realtime sessions on their own execution surface.

### `URLSessionWebSocketTransport`

`URLSessionWebSocketTransport` is the shipped live socket transport for app-side usage.

Responsibilities:

- adapt `WebSocketRequest` into a `URLRequest`
- connect with `URLSessionWebSocketTask`
- expose a type-erased `WebSocketConnection`
- normalize close frames and transport failures into `NetworkError`

### Repeated Header Behavior

Inside Comet, repeated headers are preserved in `HTTPFields`.

At the `Foundation` boundary they must be combined because `URLRequest` and `HTTPURLResponse` expose dictionary-like header APIs. Comet preserves repeated headers as long as it can, but exact repeated-field fidelity cannot survive every `Foundation` conversion path.

That means:

- repeated header intent is preserved inside `RequestBuilder`, middleware, and tests
- when adapted to `URLSession`, repeated headers are combined according to HTTP conventions

---

## Middleware

### Contract

Middleware is result-aware:

```swift
public protocol Middleware: Sendable {
    func prepare(
        _ request: PreparedRequest,
        context: MiddlewareContext
    ) async throws(NetworkError) -> PreparedRequest

    func process(
        result: Result<RawResponse, NetworkError>,
        request: PreparedRequest,
        context: MiddlewareContext
    ) async throws(NetworkError) -> MiddlewareResult
}
```

This allows retry behavior to respond to both transport failures and HTTP responses.

### Built-In Middleware

- `BearerTokenMiddleware`
- `RetryMiddleware`
- `LoggingMiddleware`

### `RetryMiddleware`

Current characteristics:

- retries retryable transport failures
- retries configurable HTTP status codes
- defaults to retrying safe methods and requests carrying an `Idempotency-Key`
- supports per-request retry opt-in or opt-out through `RequestRetryPolicy`
- uses injected sleep behavior
- uses injected random jitter behavior through `MiddlewareContext`
- emits retry activity events

### `LoggingMiddleware`

Current characteristics:

- works at runtime in debug, release, and server builds
- supports `.request`, `.response`, and `.verbose`
- uses the shared `RedactionPolicy`
- includes request metadata labels when present
- `.verbose` includes a shell-quoted cURL representation
- generated cURL output can be formatted as multiline or compact through `CURLCommandStyle`
- generated cURL bodies can preserve original text or pretty-print JSON through `CURLCommandOptions`

---

## Observability

### `NetworkEvent`

Current event surface:

- `.requestStarted`
- `.requestCompleted`
- `.requestFailed`
- `.requestRetried`

`NetworkEvent` also exposes computed diagnostic properties so callers can inspect activity without pattern matching every event case:

- `kind`
- `id`
- `metadata`
- `displayName`
- `method`
- `url`
- `statusCode`
- `duration`
- `error`
- `retryAttempt`
- `retryDelay`
- `diagnosticSummary`

### `HTTPClient.activity`

`activity` exposes a multicast `AsyncStream<NetworkEvent>`.

Important behavior:

- each subscriber gets its own stream
- registration and removal are synchronous inside the broadcaster
- events include request metadata when present
- events represent request execution, not post-decode business success

The broadcaster is currently a small lock-backed reference type rather than an actor. That keeps subscription setup simple and avoids registration races.

---

## Deduplication

`RequestDeduplicator` coalesces concurrent requests by key.

Important behavior:

- opt-in only
- shared task cleanup happens when the underlying task finishes
- multiple callers can await the same transport work

Current guarantee:

- concurrent callers using the same `deduplicationKey` share one underlying request

---

## Errors

Current public error surface:

```swift
public enum NetworkError: Error, Sendable {
    case invalidRequest(String)
    case transport(URLError)
    case http(statusCode: Int, body: Data, headers: HTTPFields)
    case webSocketClosed(code: WebSocketCloseCode, reason: Data?)
    case decoding(DecodingError)
    case encoding(String)
    case middleware(String)
    case cancelled
    case timeout
    case unknown(any Error & Sendable)
}
```

Design notes:

- the client uses typed throws at the public boundary
- `NetworkError` is `Sendable`
- it is intentionally not `Equatable`

---

## Testing Support

### `CometTesting`

Current helpers:

- `MockTransport`
- `MockWebSocketTransport`
- `RecordingTransport`
- `ReplayTransport`
- `HTTPCassette`
- `HTTPClient.mock`
- `HTTPClient.succeeding`
- `HTTPClient.failing`

### `MockTransport`

Current modes:

- `responses(_:)` for simple path-based mapping
- `routes(_:)` for method/path/query-aware matching

This is the main low-friction testing seam for request code.

### `MockWebSocketTransport`

`MockWebSocketTransport` is the realtime equivalent:

- record handshake requests
- optionally echo sent messages
- queue inbound messages deterministically
- track ping and close behavior

### Recorder And Replay

`RecordingTransport` now records full exchanges, not just requests:

- request URL, method, headers, body, and timeout
- response status, headers, body, or the resulting `NetworkError`
- exchange duration and recording timestamp

`HTTPCassette` serializes those exchanges as JSON fixtures, and `ReplayTransport` plays them back either by matching requests or by consuming them sequentially.

---

## TCA Integration

`CometTCA` is intentionally small.

Current surface:

- `DependencyValues.httpClient`
- `Effect.request`

This keeps the core package free of `swift-dependencies` and TCA-specific concerns.

---

## Playground App

`Examples/CometPlayground` is a generated iOS app used to exercise the package.

It currently demonstrates:

- typed JSON decoding
- text responses
- empty responses
- raw responses
- WebSocket echo transcripts
- mock vs live client modes
- activity event viewing

The project is generated from `project.yml` with XcodeGen.

---

## Current Limitations

- the shipped live transports are `URLSession`-backed and Apple-platform specific
- server-side Swift support currently means the core abstractions are transport-replaceable, not that a Vapor/AsyncHTTPClient transport ships today
- repeated headers are preserved inside Comet but combined at `Foundation` boundaries
- activity events cover request lifecycle, not decode lifecycle
- WebSocket session activity is modeled through `WebSocketSessionEvent`, not `NetworkEvent`
- server-side live transports are deferred for `0.3.0`; see [Server Transport Decision](technical/SERVER_TRANSPORT_DECISION.md)
- stale-while-revalidate refreshes update cache storage in the background but do not currently emit their own public `NetworkEvent` or completed `RequestTrace`

---

## Next Likely Additions

When Comet grows beyond this release line, the highest-value next additions are likely:

- richer generated-model support for OpenAPI schemas
- an explicit server-side live transport after a dependency decision
