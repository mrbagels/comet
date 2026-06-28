# Changelog

All notable changes to Comet are documented here.

Comet is still pre-1.0. The `0.2.0` release cut contains the completed V2
foundation. The `0.3.0` release adds caching, code generation, contract testing,
and the playground proof flows that make those systems easier to inspect.
The `0.4.0` release expands that V3 foundation with schema-aware generation,
YAML OpenAPI input, optional SQLiteData persistence, TCA playground coverage,
and cache and middleware hardening. It includes a `CometTCA` API break where the
request effect helper now returns `Effect<Action>` instead of the underscored
`_Effect<Action>` spelling.
The `0.4.1` patch release adds stale-while-revalidate caching, proof bundle
exports in the playground, and a SwiftPM OpenAPI command plugin while preserving
the `0.4.0` public API contract.

## 0.4.1 - 2026-06-28

### Added

- `HTTPCachePolicy.staleWhileRevalidate` for serving stale cached responses immediately while a background refresh updates storage.
- Background cache refresh scheduling with validator reuse and per-key refresh coalescing.
- Playground proof bundles that package request inspection, traces, responses, cassettes, contract reports, and output into copyable Markdown artifacts.
- Activity-tab browsing for persisted proof bundles.
- `CometOpenAPIPlugin`, a SwiftPM command plugin for package-root OpenAPI generation.

### Changed

- Stale-while-revalidate tracing reuses the existing cache event vocabulary so the patch release stays source-compatible with exhaustive client switches.

### Fixed

- Kept the cache refresh policy patch-safe by avoiding new public enum cases in `HTTPCachePolicy.Strategy` and `RequestCacheTraceEvent`.

## 0.4.0 - 2026-06-28

### Added

- Schema-aware OpenAPI generation for component models, local `$ref`s, typed JSON success serializers, and typed error-response hooks.
- YAML OpenAPI input support through Yams.
- `CometSQLiteData` as an optional SQLiteData-backed product for persisted activity events and generated artifacts.
- Playground saved activity history backed by `CometSQLiteData`.
- Playground TCA tab for a reducer-backed `CometTCA` request flow.

### Changed

- `CometTCA` request effects now use the public `Effect<Action>` return type instead of the underscored `_Effect<Action>` spelling.
- Hardened cache, streaming, middleware, authentication, and WebSocket edge cases.
- Improved `CometTCA` request effect ergonomics and playground SwiftUI state flow.
- Polished API-diff and simulator smoke tooling for local and CI verification.

### Fixed

- Restored cache API compatibility for existing request cache policy call sites.

## 0.3.0 - 2026-06-28

### Added

- `0.3.0` release train plan in Markdown and static HTML, with patch milestones from `0.2.x` through the final minor release.
- Fresh external client smoke script for validating package adoption outside this repository.
- `TraceContext` and `TracePropagationMiddleware` for W3C `traceparent` propagation.
- Propagated trace IDs on `RequestMetadata` and completed `RequestTrace` values.
- Playground raw-response proof that shows the outbound trace header in mock mode.
- `HTTPCachePolicy`, `HTTPCacheKey`, `CachedHTTPResponse`, `HTTPCacheStore`, and `MemoryHTTPCacheStore`.
- `HTTPCacheControl` and `HTTPCacheMetadata` for typed `Cache-Control`, `Expires`, `ETag`, and `Last-Modified` parsing.
- `CacheMiddleware` for opt-in safe-method response caching.
- HTTP cache revalidation with conditional `If-None-Match` and `If-Modified-Since` requests, `304 Not Modified` merge behavior, and replacement storage for refreshed `200` responses.
- Cache-only, network-only, return-cache-else-load, reload-ignoring-cache, and revalidate request policies.
- Cache hit, miss, bypass, stale, revalidate, update, store, and skipped-store events on completed `RequestTrace` values.
- `FileHTTPCacheStore` and `FileHTTPCacheStoreConfiguration` for namespace-isolated persistent cache entries with size limits, oldest-entry pruning, and corrupted-entry cleanup.
- Stale-if-error cache fallback through `HTTPCachePolicy(allowsStaleIfError:)`.
- Playground cache lab scenario covering first load, fresh cache hit, stale revalidation, offline stale fallback, and clear cache.
- `ContractExpectation`, `ContractTransport`, `ContractReport`, and `MockServer` for strict request contract testing and JSON report export.
- Cassette-to-contract conversion for turning recorded fixtures into strict transport expectations.
- `CometOpenAPIGenerator` and `comet-openapi-generate` for dependency-free JSON OpenAPI request generation.
- `ReachabilitySnapshot`, `ReachabilityHintProvider`, and `StaticReachabilityHintProvider` for app-owned reachability hints.
- `CometRequestState` for lightweight TCA request loading, value, and failure state.
- Playground contract server scenario covering strict expectation matching and clean contract reports.

### Changed

- Playground test target now links `HTTPTypes` directly to match the app target and reduce Xcode dependency-scan ambiguity.

## 0.2.0 - 2026-06-28

### Added

- Playground response viewer snapshots for demo output, HTTP metadata, failure bodies, and socket transcript results.
- Playground socket monitor snapshots for realtime frames, transports, subprotocols, and close codes.
- Playground cassette viewer exports deterministic mock HTTP scenarios as `CometTesting` cassette JSON.
- `WebSocketConnection.messages()` for consuming socket frames as an `AsyncThrowingStream`.
- Playground trace timeline panels group request and socket activity by demo.
- Playground cassette replay verification checks exported mock cassettes with `ReplayTransport`.
- `HTTPClient.traces` emits completed `RequestTrace` values with attempts, retry delays, timings, bytes, metadata, and final outcomes.
- `AuthenticationCoordinator` and `AuthenticationMiddleware` provide token reads, refresh de-duplication, and safe 401 replay.
- Streaming and transfer primitives with `HTTPClient.stream`, `HTTPClient.lines`, `HTTPClient.serverSentEvents`, `HTTPStreamingTransport`, and progress-aware `sendRaw`.
- `WebSocketSession` adds a resilient actor wrapper with lifecycle events, message streams, and bounded reconnect attempts.

## 0.1.5 - 2026-06-28

### Added

- Typed API error decoding with `ErrorResponseSerializer`, `APIRequestWithErrorResponse`, `APIClientError`, and `HTTPClient.sendWithTypedErrors`.
- cURL command options for pretty-printed JSON request bodies and configurable verbose logging output.
- A CI API stability gate that fails on public API breaks against the latest release tag.
- DocC workflow tutorials for authenticated JSON, retries and activity, typed errors, testing and cassettes, WebSockets, and TCA integration.
- Playground failure-gallery scenarios for timeout, 401 typed errors, 429 retry, 500 errors, malformed JSON, cancellation, and WebSocket close diagnostics.
- `HTTPClient.prepare(_:)` plus playground request inspectors and structured activity detail screens.

## 0.1.4 - 2026-06-27

### Added

- Query item helpers for optional values, boolean flags, repeated items, joined collections, and date encodings.
- Diagnostic computed properties on `NetworkEvent` for event kind, metadata, status, duration, retry details, and summaries.
- cURL command formatting styles for multiline and compact output.

### Changed

- `QueryItemsBuilder` now accepts arrays of optional query items and drops absent values.

## 0.1.3 - 2026-06-27

### Added

- Playground app icon set generated from the Comet gradient mark.

### Changed

- Restored the XcodeGen app icon compiler setting now that the playground has a valid `AppIcon` asset.

## 0.1.2 - 2026-06-27

### Added

- First-party SVG brand assets under `Resources/Brand`.
- Playground app asset catalog support for the Comet gradient icon.

### Changed

- Reworked the README with the Comet mark, release badges, clearer package positioning, and updated installation instructions.
- Added brand polish to the playground README and home screen.

## 0.1.1 - 2026-06-27

### Added

- WebSocket client, transport, request, connection, and mock transport support.
- Request activity events with configurable buffering.
- Cassette recording and replay fixtures in `CometTesting`.
- Request metadata for logs, activity events, and future traces.
- Shared redaction policy for logging, cURL output, and cassette recording.
- Status validation presets for not-modified, redirect, and no-content workflows.
- Public repository metadata: license, contribution guide, security policy, and changelog.
- CI guardrails for secret scanning and public API diff reporting.

### Changed

- Clarified the Swift 6.2, iOS 18, macOS 15, and visionOS 2 support policy.
- Tightened intentionally public API surface around internal activity broadcasting and request deduplication.
- `RetryMiddleware` now uses conservative retry safety by default: safe methods retry automatically, while write requests require an idempotency key or explicit request retry policy.
- cURL generation now shell-quotes arguments and uses the shared redaction policy.

### Security

- Cassette recording now redacts sensitive HTTP headers by default and supports request/response body redaction hooks.

## 0.1.0 - 2026-04-01

### Added

- Initial release baseline for typed HTTP requests, response serializers, middleware, retry behavior, deduplication, activity events, testing transports, and TCA integration.
