# ``CometTesting``

Deterministic testing tools for Comet-powered networking.

## Overview

`CometTesting` keeps mocks and fixture workflows out of your production client surface while preserving the same request and transport model used at runtime.

Use it for:

- fully in-memory unit tests with ``MockTransport``
- fully in-memory realtime tests with ``MockWebSocketTransport``
- recording live traffic with ``RecordingTransport``
- redacting sensitive cassette data with ``RecordingRedaction``
- serializing recordings as JSON with ``HTTPCassette``
- replaying fixtures deterministically with ``ReplayTransport``
- validating strict request contracts with ``ContractTransport``
- running higher-level mock scenarios with ``MockServer``
- exporting contract reports with ``ContractReport``

## Topics

### Fast Tests

- ``MockTransport``
- ``MockWebSocketTransport``
- ``HTTPClient/mock(baseURL:handler:)``
- ``HTTPClient/succeeding(with:baseURL:statusCode:headers:)``
- ``HTTPClient/failing(baseURL:with:)``

### Recorder And Replay

- ``RecordingTransport``
- ``RecordingRedaction``
- ``HTTPCassette``
- ``ReplayTransport``
- ``RecordedExchange``

### Contracts

- <doc:ContractTesting>
- ``ContractExpectation``
- ``ContractTransport``
- ``ContractReport``
- ``ContractViolation``
- ``ContractMatch``
- ``ContractDifference``
- ``MockServer``
