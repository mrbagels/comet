# Comet Playground

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
- `Proofs`: category-driven scenarios with detail pages
- `Activity`: filtered request event history
- `Demo detail`: focused output, verification, and rerun controls

## Recommended Verification Flow

### 1. Start In Mock Mode

Run `Mock Proof` first. All four scenarios should pass.

Expected outputs:

- `Typed JSON`: output contains `Mock transport says hello`
- `Plain Text`: output contains `Comet mock text response`
- `Empty Response`: output confirms `Received an EmptyResponse successfully.`
- `Raw Response`: output shows `status: 200` and `content-type: application/json`

The activity feed should populate with started and completed events for each request.

### 2. Run A Live Spot Check

Switch to `Live` mode and re-run any scenario.

Good checks:

- `Typed JSON`: should return a real todo from JSONPlaceholder
- `Plain Text`: should include the Example Domain page text
- `Empty Response`: should complete successfully against the live 204-style endpoint
- `Raw Response`: should show a non-empty payload with real response metadata

### 3. Inspect Package Usage

Each scenario in the UI shows the exact Comet API surface it is proving. The demo app currently exercises:

- `HTTPClient.send`
- `HTTPClient.sendRaw`
- `APIRequest`
- `Path`
- `ResponseSerializer.json`
- `ResponseSerializer.string`
- `RequestOptions.absoluteURL`
- `EmptyResponse`
- `RawResponse`
- `NetworkEvent`

## Useful Files

- [App/DemoCatalog.swift](App/DemoCatalog.swift): shared state and run logic
- [App/RootView.swift](App/RootView.swift): tab shell
- [App/HomeTab.swift](App/HomeTab.swift): landing experience and launch actions
- [App/ProofsTab.swift](App/ProofsTab.swift): proof navigation and category flows
- [App/ActivityTab.swift](App/ActivityTab.swift): event stream and filtering
- [App/DemoDetailScreen.swift](App/DemoDetailScreen.swift): focused scenario detail screen
- [App/PlaygroundStyle.swift](App/PlaygroundStyle.swift): shared liquid glass styling and UI primitives
- [App/DemoRequests.swift](App/DemoRequests.swift): request definitions
- [App/DemoClientFactory.swift](App/DemoClientFactory.swift): mock and live client wiring
- [project.yml](project.yml): XcodeGen target configuration

## Command-Line Checks

iOS:

```sh
xcodebuild test -project CometPlayground.xcodeproj -scheme CometPlaygroundApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'
```

## Extending The Demo Lab

When you add a new proof scenario:

1. Add the request type in [App/DemoRequests.swift](App/DemoRequests.swift).
2. Add mock or live client support in [App/DemoClientFactory.swift](App/DemoClientFactory.swift).
3. Add demo metadata and run logic in [App/DemoCatalog.swift](App/DemoCatalog.swift).
4. Surface it in the appropriate tab or detail flow from [App/RootView.swift](App/RootView.swift).
