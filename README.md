# Comet

Comet is a modern Swift networking library built as a Swift package for long-term reuse across app projects today, with a transport seam designed to grow into broader environments over time.

## Package Products

- `Comet`: core request building, serialization, transport, middleware, retry, deduplication, and activity events
- `CometTesting`: mock and recording transports for deterministic verification
- `CometTCA`: lightweight Composable Architecture integration

## Repository Layout

- `Sources/`: package source targets
- `Tests/`: package test targets
- `Examples/CometPlayground/`: XcodeGen-driven iOS demo app
- `docs/ARCHITECTURE.md`: architecture notes
- `docs/IMPLEMENTATION_PLAN.md`: implementation plan and rollout notes

## Quick Start

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
xcodebuild test -project CometPlayground.xcodeproj -scheme CometPlaygroundApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'
```

## Example App

The example project is an iPhone-first verification app for the package. It gives you:

- an iOS app target: `CometPlaygroundApp`
- a focused smoke test target: `CometPlaygroundTests`
- deterministic mock verification with `CometTesting.MockTransport`
- live transport checks through `URLSessionTransport`
- focused proof, activity, and detail flows showing which APIs are being exercised and what output to verify

The full walkthrough lives in [Examples/CometPlayground/README.md](Examples/CometPlayground/README.md).

## What To Open First

If you want to understand or modify the example apps, start here:

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
