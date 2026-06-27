# Comet MVP Status And Implementation Plan

> This file now serves two purposes:
> 1. record what the MVP already implements
> 2. define the narrow follow-up work that still makes sense before broader feature growth

---

## Current Status

The MVP described for Comet has been implemented in this repository.

What exists today:

- Swift package with `Comet`, `CometTCA`, and `CometTesting`
- generated iOS playground app using XcodeGen
- typed request pipeline built around `APIRequest`, `HTTPBody`, and `ResponseSerializer`
- pluggable transport seam with `URLSessionTransport`
- pluggable WebSocket seam with `WebSocketClient` and `URLSessionWebSocketTransport`
- route safety via `Path`
- request-level and global middleware
- retry behavior with injected randomness and sleep
- runtime logging middleware
- in-flight deduplication
- request activity stream
- mock WebSocket sessions for tests and demos
- test utilities and TCA integration
- DocC workflow tutorials for core package usage

Verified commands:

- `swift test --disable-xctest`
- `xcodebuild test -scheme CometPlaygroundApp -project CometPlayground.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'`

---

## Delivered Package Layout

```text
Package.swift
Sources/
  Comet/
  CometTCA/
  CometTesting/
Tests/
  CometTests/
  CometTCATests/
  CometTestingTests/
Examples/
  CometPlayground/
    project.yml
    CometPlayground.xcodeproj
Resources/
  Brand/
    icon-gradient.svg
    logo-mark.svg
    logo-text.svg
```

---

## Phase Status

### Phase 0: Contracts And Scaffolding

Completed.

Delivered:

- package boundaries
- docs folder
- `Package.swift`
- XcodeGen project definition
- generated playground project

### Phase 1: Core Request / Response Foundation

Completed.

Delivered:

- `HTTPMethod`
- `QueryItem`
- `Path`
- `HTTPBody`
- `ResponseSerializer`
- `RawResponse`
- `EmptyResponse`
- `StatusValidation`
- `RequestOptions`
- `NetworkError`
- `APIRequest`
- `PreparedRequest`
- `ClientConfiguration`
- `RequestBuilder`
- `HTTPTransport`
- `URLSessionTransport`
- `HTTPClient`

### Phase 2: Middleware, Deduplication, Observability

Completed.

Delivered:

- result-aware middleware contract
- middleware chain
- `BearerTokenMiddleware`
- `RetryMiddleware`
- `LoggingMiddleware`
- `RequestDeduplicator`
- `NetworkEvent`
- `EventBroadcaster`
- debug cURL rendering

### Phase 3: Testing Helpers And Playground

Completed.

Delivered:

- `MockTransport`
- `MockWebSocketTransport`
- `RecordingTransport`
- JSON cassette export and replay
- `HTTPClient` testing factories
- generated iOS playground app
- mock and live demo flows
- WebSocket demo flow

### Phase 4: Minimal TCA Support

Completed.

Delivered:

- `DependencyValues.httpClient`
- `Effect.request`

### Phase 5: Hardening Pass

Completed for the current MVP.

Delivered:

- retry jitter connected to injected randomness
- logging semantics fixed and runtime-enabled
- repeated headers preserved inside Comet
- request status validation surface added
- richer `MockTransport` route matching
- safer text body encoding behavior
- default JSON behavior made less opinionated
- stronger package and playground coverage

### Phase 6: Realtime Support

Completed.

Delivered:

- `WebSocketRequest`
- `WebSocketConnection`
- `WebSocketTransport`
- `WebSocketClient`
- `URLSessionWebSocketTransport`
- `MockWebSocketTransport`
- package coverage for WebSocket request building and mock socket sessions
- demo app coverage for a focused WebSocket echo proof

### Phase 7: Public Documentation

In progress.

Delivered:

- authenticated JSON tutorial
- retries and activity tutorial
- typed API errors tutorial
- testing and cassettes tutorial
- WebSockets tutorial
- TCA integration tutorial

---

## Implemented Core Decisions

The following architectural decisions are no longer tentative:

- Comet is not centered on `URLRequest`
- `HTTPTransport` is the long-term transport seam
- `RequestOptions` groups optional request behavior
- status validation belongs to request options, not to serializers
- middleware is result-aware
- retry timing is injectable and deterministic in tests
- activity events represent request execution
- `CometTCA` remains intentionally minimal
- `CometTesting` is the main test-support product

---

## Current Test Coverage

### Package Tests

The package tests currently cover:

- path construction
- absolute URL resolution
- JSON request/response flow
- custom status validation
- repeated header preservation
- empty responses
- safer text body encoding failure
- JSON preset behavior
- retry event emission and deterministic jitter
- deduplication for concurrent callers
- logging middleware behavior
- mock route matching
- recording transport request/response/failure capture
- cassette JSON round-tripping
- replay transport fixtures
- WebSocket request building and mock session control
- TCA dependency and effect integration

### Playground Tests

The generated playground app currently covers:

- initial mock-mode startup on iOS
- executing the mock proof flow end to end, including the WebSocket echo demo

---

## Recommended Final Sweep

Yes, one more final overall sweep is still worth doing, but it should be a short polish pass rather than another redesign.

Recommended scope:

1. Public API naming review
2. Quick-start usage examples in docs
3. Package ergonomics check from a fresh client package or app target
4. Lightweight server-side story review
5. CI automation and repeatable commands

### What That Sweep Should Look For

- awkward names before wider adoption
- anything that feels too hidden or too clever in the public API
- missing top-level examples for common usage
- any remaining docs/code drift
- any platform or package integration surprises

### What That Sweep Should Not Become

- a new architecture pass
- broad new feature work
- server-side transport expansion
- cache/tracing/SSE design work

---

## Recommended Near-Term Follow-Up

If we keep tightening before real project adoption, the highest-value follow-ups are:

- add a fresh-client integration smoke check outside this repository
- add richer DocC walkthroughs for cassette and WebSocket flows
- evaluate whether WebSocket activity should have a first-class event surface
- add a small “server-side direction” note once the future transport choice is made

---

## Deferred Roadmap

These remain intentionally out of the MVP:

- server-side live transport implementation
- distributed tracing
- caching
- ETag support
- mock server
- reachability
- streaming APIs
- upload/download APIs
- higher-level TCA domain helpers

They should only be added after the current API is used in real projects and proves stable.
