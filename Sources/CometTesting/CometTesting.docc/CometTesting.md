# ``CometTesting``

Deterministic testing tools for Comet-powered networking.

## Overview

`CometTesting` keeps mocks and fixture workflows out of your production client surface while preserving the same request and transport model used at runtime.

Use it for:

- fully in-memory unit tests with ``MockTransport``
- fully in-memory realtime tests with ``MockWebSocketTransport``
- recording live traffic with ``RecordingTransport``
- serializing recordings as JSON with ``HTTPCassette``
- replaying fixtures deterministically with ``ReplayTransport``

## Topics

### Fast Tests

- ``MockTransport``
- ``MockWebSocketTransport``
- ``HTTPClient/mock(baseURL:handler:)``
- ``HTTPClient/succeeding(with:baseURL:statusCode:headers:)``
- ``HTTPClient/failing(baseURL:with:)``

### Recorder And Replay

- ``RecordingTransport``
- ``HTTPCassette``
- ``ReplayTransport``
- ``RecordedExchange``
