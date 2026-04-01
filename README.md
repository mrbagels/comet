# Comet

Comet is a modern Swift networking library for Apple-platform apps today. It ships with a `URLSession`-backed live transport and a transport seam that also supports mocks, recorders, replayers, and future non-`URLSession` transports.

## Package Products

- `Comet`: typed request building, serialization, middleware, retry, deduplication, and activity events
- `CometTesting`: mocks, recorders, JSON cassettes, and replay transports
- `CometTCA`: lightweight Composable Architecture integration

## Platform Status

Comet’s shipped live transport is `URLSessionTransport`, so the production-ready story today is Apple-platform client apps. The core abstractions are intentionally transport-replaceable, but a server-side live transport does not ship yet.

## Install

```swift
.package(url: "https://github.com/mrbagels/comet.git", from: "0.1.0")
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

GitHub Actions runs both the Swift package suite and the iOS example smoke tests on every push to `master` and `dev`.

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
