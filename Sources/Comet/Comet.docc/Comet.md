# ``Comet``

Typed HTTP requests and WebSocket connections for modern Swift apps.

## Overview

Comet centers on three concepts:

- ``APIRequest`` models a typed request and response pair.
- ``HTTPClient`` executes requests with shared configuration and middleware.
- ``HTTPTransport`` performs the actual I/O, which keeps the core testable and replaceable.
- ``WebSocketClient`` manages realtime sessions through a separate but matching transport seam.

The shipped live transports today are ``URLSessionTransport`` and ``URLSessionWebSocketTransport``, which makes Comet production-ready for Apple-platform client apps. The transport seams are intentionally open so the same public model can also power mocks, recorders, replayers, and future non-`URLSession` transports.

## Topics

### Workflow Tutorials

- <doc:AuthenticatedJSON>
- <doc:RetriesAndActivity>
- <doc:TypedErrors>
- <doc:TestingAndCassettes>
- <doc:WebSockets>
- <doc:TCAIntegration>

### Essentials

- ``APIRequest``
- ``HTTPClient``
- ``ClientConfiguration``
- ``RequestOptions``
- ``RequestMetadata``
- ``PreparedRequest``
- ``ResponseSerializer``
- ``ErrorResponseSerializer``
- ``APIRequestWithErrorResponse``
- ``HTTPBody``
- ``Path``
- ``QueryItem``
- ``QueryDateEncodingStyle``

### Transport And Errors

- ``HTTPTransport``
- ``URLSessionTransport``
- ``WebSocketTransport``
- ``WebSocketClient``
- ``WebSocketRequest``
- ``WebSocketConnection``
- ``URLSessionWebSocketTransport``
- ``RawResponse``
- ``NetworkError``
- ``APIClientError``
- ``DecodedErrorResponse``

### Middleware And Activity

- ``Middleware``
- ``AuthenticationCredential``
- ``AuthenticationCoordinator``
- ``AuthenticationMiddleware``
- ``BearerTokenMiddleware``
- ``RetryMiddleware``
- ``RequestRetryPolicy``
- ``LoggingMiddleware``
- ``CURLCommandStyle``
- ``CURLCommandBodyFormatting``
- ``CURLCommandOptions``
- ``NetworkEvent``
- ``RequestTrace``
- ``RequestTraceAttempt``
- ``RequestTraceResult``
- ``NetworkActivityBufferingPolicy``
- ``RedactionPolicy``
