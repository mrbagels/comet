# Contract Testing

Validate request shape drift with strict transport-level contracts.

## Overview

Use ``ContractTransport`` when a test should prove that a typed request still sends
the expected method, path, query items, headers, body, and metadata.

```swift
let transport = ContractTransport(
  expectations: [
    ContractExpectation(
      id: "get-profile",
      method: .get,
      path: "/profile",
      headers: [
        ContractHeaderExpectation(name: "accept", value: .exact("application/json"))
      ],
      outcome: .response(
        RawResponse(data: Data(#"{"name":"Comet"}"#.utf8), statusCode: 200)
      )
    )
  ]
)
```

When a request matches, the expectation is consumed. When a request mismatches,
``ContractTransport`` throws and records a ``ContractViolation``. At the end of a
test, call ``ContractTransport/verifyComplete()`` so unused expectations fail too.

```swift
_ = try await client.send(GetProfile())
try await transport.verifyComplete()
```

## Reports

Contract reports are JSON-exportable for CI artifacts:

```swift
let report = await transport.report()
try report.write(to: reportURL)
```

## Cassettes

Recorded cassettes can be promoted into strict contracts:

```swift
let cassette = try HTTPCassette(contentsOf: fixtureURL)
let server = try MockServer(cassette: cassette)
```

Use ``MockServer`` when a demo, preview, or UI test wants the same scenario
definitions used by package tests.
