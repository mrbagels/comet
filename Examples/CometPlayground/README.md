<p align="center">
  <img src="../../Resources/Brand/icon-gradient.svg" alt="Comet logo" width="88">
</p>

<h1 align="center">Comet Playground</h1>

Comet Playground is the package verification app for this repository. It is generated with XcodeGen and ships as an iOS app target backed by the local Swift package.

## Targets

- `CometPlaygroundApp`: iOS example app
- `CometPlaygroundTests`: iOS smoke tests

## Generate The Project

```sh
xcodegen generate
```

Open `CometPlayground.xcodeproj` in Xcode after generation, or use `xcodebuild` directly.

## Current App Shape

The app is organized as a modern iPhone-native demo:

- `Home`: quick launch, mode switching, and session summary
- `Proofs`: category-driven HTTP and realtime scenarios with detail pages
- `Activity`: filtered structured request history, saved SQLiteData history, socket session markers, and detail fields
- `Socket Monitor`: realtime frame, endpoint, transport, subprotocol, and close-code inspection
- `Demo detail`: focused output, request inspector, trace timeline, response viewer, cassette viewer, verification, and rerun controls

## Recommended Verification Flow

### 1. Start In Mock Mode

Run `Mock Proof` first. All success, failure, and realtime scenarios should pass.

Expected outputs:

- `Typed JSON`: output contains `Mock transport says hello`
- `Plain Text`: output contains `Comet mock text response`
- `Empty Response`: output confirms `Received an EmptyResponse successfully.`
- `Raw Response`: output shows `status: 200` and `content-type: application/json`
- `Cache Lab`: output shows a first load, fresh hit, stale revalidation, offline stale fallback, and cleared cache
- `Contract Server`: output shows a passing contract report with one matched expectation and zero violations
- `Timeout`: output records a timeout-shaped `NetworkError`
- `Typed 401`: output includes the mock `unauthorized` error code
- `429 Retry`: output confirms recovery after a retry
- `Server Error`: output preserves the `500` status code
- `Malformed JSON`: output identifies a decoding error
- `Cancellation`: output identifies cancellation explicitly
- `WebSocket Echo`: output shows `MockWebSocketTransport` and the negotiated `comet.demo.v1` subprotocol
- `Socket Close`: output shows a WebSocket close error

The activity feed should populate with structured started, completed, failed, retried, and socket events. Open any activity detail to inspect request IDs, metadata, status, retry delay, error summaries, and copyable raw text.

Each completed detail screen groups the matching request or socket activity into a trace timeline with ordered events and a copyable trace snapshot.

Each completed detail screen also shows a response viewer with structured fields, body output, and a copyable snapshot for the latest success, failure, or socket result.

Realtime detail screens include a socket monitor with outbound, inbound, and close frames plus a copyable monitor snapshot.

Mock HTTP detail screens include a cassette viewer that exports the latest scenario through `RecordingTransport` as copyable `HTTPCassette` JSON and verifies it with `ReplayTransport`.

### 2. Run A Live Spot Check

Switch to `Live` mode and re-run any scenario.

Good checks:

- `Typed JSON`: should return a real todo from JSONPlaceholder
- `Plain Text`: should include the Example Domain page text
- `Empty Response`: should complete successfully against the live 204-style endpoint
- `Raw Response`: should show a non-empty payload with real response metadata
- `Cache Lab`: should run the deterministic local cache flow and clear its file store
- `Contract Server`: should run the deterministic local contract scenario and export a clean report
- `Timeout`: should report a timeout-shaped failure against a delayed endpoint
- `Typed 401`: should preserve a live 401 status
- `429 Retry`: should exercise retry behavior against a live 429 response
- `Server Error`: should preserve a live 500 status
- `Malformed JSON`: should report a decoding failure
- `Cancellation`: should report deterministic cancellation
- `WebSocket Echo`: should connect to `wss://ws.postman-echo.com/raw` and echo the JSON payload back into the transcript
- `Socket Close`: should report a deterministic close-frame failure

### 3. Inspect Package Usage

Each scenario in the UI shows the exact Comet API surface it is proving. The demo app currently exercises:

- `HTTPClient.prepare`
- `HTTPClient.send`
- `HTTPClient.sendRaw`
- `APIRequest`
- `Path`
- `ResponseSerializer.json`
- `ResponseSerializer.string`
- `RequestOptions.absoluteURL`
- `EmptyResponse`
- `RawResponse`
- `CacheMiddleware`
- `FileHTTPCacheStore`
- `HTTPCachePolicy`
- `RequestTrace.cacheEvents`
- `MockServer`
- `ContractExpectation`
- `ContractTransport`
- `ContractReport`
- `NetworkEvent`
- `RetryMiddleware`
- `APIRequestWithErrorResponse`
- `APIClientError`
- `WebSocketClient.connect`
- `WebSocketRequest`
- `URLSessionWebSocketTransport`
- `MockWebSocketTransport`
- `PreparedRequest.curlCommand`
- `RecordingTransport`
- `HTTPCassette`
- `CometSQLiteData`
- `@FetchAll`

## Useful Files

- [App/DemoCatalog.swift](App/DemoCatalog.swift): shared state and run logic
- [App/RootView.swift](App/RootView.swift): tab shell
- [App/HomeTab.swift](App/HomeTab.swift): landing experience and launch actions
- [App/ProofsTab.swift](App/ProofsTab.swift): proof navigation and category flows
- [App/ActivityTab.swift](App/ActivityTab.swift): event stream and filtering
- [App/Schema.swift](App/Schema.swift): SQLiteData database bootstrap
- [App/DemoDetailScreen.swift](App/DemoDetailScreen.swift): focused scenario detail screen
- [App/PlaygroundStyle.swift](App/PlaygroundStyle.swift): shared liquid glass styling and UI primitives
- [App/DemoRequests.swift](App/DemoRequests.swift): request definitions
- [App/DemoClientFactory.swift](App/DemoClientFactory.swift): mock and live HTTP/WebSocket wiring
- [App/Assets.xcassets](App/Assets.xcassets): bundled Comet brand icon and app icon
- [project.yml](project.yml): XcodeGen target configuration

## Command-Line Checks

iOS:

```sh
SIMULATOR_ID="$(../../.github/scripts/select-ios-simulator.sh)"
xcodebuild test -project CometPlayground.xcodeproj -scheme CometPlaygroundApp -destination "platform=iOS Simulator,id=$SIMULATOR_ID" SWIFT_ENABLE_EXPLICIT_MODULES=NO
```

## Extending The Demo Lab

When you add a new proof scenario:

1. Add the request type or socket flow model in [App/DemoRequests.swift](App/DemoRequests.swift) or [App/DemoModels.swift](App/DemoModels.swift).
2. Add mock or live client support in [App/DemoClientFactory.swift](App/DemoClientFactory.swift).
3. Add demo metadata and run logic in [App/DemoCatalog.swift](App/DemoCatalog.swift).
4. Surface it in the appropriate tab or detail flow from [App/RootView.swift](App/RootView.swift).
