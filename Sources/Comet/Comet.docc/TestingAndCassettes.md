# Testing And Cassettes

Use in-memory mocks for fast unit tests and cassettes for higher-fidelity replay workflows.

## Mock Transport

`MockTransport` lets tests register deterministic responses without a server.

```swift
let client = HTTPClient.live(
  configuration: .default(baseURL: URL(string: "https://api.example.com")!),
  transport: MockTransport { request in
    guard request.url.path == "/users/42" else {
      throw NetworkError.invalidRequest("Unexpected request.")
    }

    return RawResponse(
      data: Data(#"{"id":42,"name":"Blob"}"#.utf8),
      statusCode: 200
    )
  }
)

let user = try await client.send(GetUser(userID: 42))
```

## Record Once

`RecordingTransport` wraps another transport and captures request and response pairs.

```swift
let recorder = RecordingTransport(base: URLSessionTransport())
let client = HTTPClient.live(
  configuration: .default(baseURL: URL(string: "https://api.example.com")!),
  transport: recorder
)

_ = try await client.send(GetUser(userID: 42))

let cassette = await recorder.cassette()
try cassette.write(to: fixtureURL)
```

## Replay Later

```swift
let replay = try ReplayTransport(contentsOf: fixtureURL)
let client = HTTPClient.live(
  configuration: .default(baseURL: URL(string: "https://api.example.com")!),
  transport: replay
)
```

Recorded fixtures can contain sensitive payloads. Use ``RedactionPolicy`` or `RecordingRedaction` before writing cassettes, and review fixture JSON before committing it.

## Contract Testing

Use `ContractTransport` from `CometTesting` when replay should also validate the
request shape.

```swift
let expectations = try cassette.contractExpectations()
let transport = ContractTransport(expectations: expectations)
let client = HTTPClient.live(
  configuration: .default(baseURL: URL(string: "https://api.example.com")!),
  transport: transport
)

_ = try await client.send(GetUser(userID: 42))
try await transport.verifyComplete()
```

For demo apps and UI tests, `MockServer` wraps the same expectations and can
export a JSON `ContractReport` for diagnostics.
