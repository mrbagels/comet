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
- <doc:CacheAwareRequests>
- <doc:RetriesAndActivity>
- <doc:RequestTracing>
- <doc:StreamingAndProgress>
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
- ``HTTPCachePolicy``
- ``HTTPCacheKey``
- ``CachedHTTPResponse``
- ``HTTPCacheStore``
- ``MemoryHTTPCacheStore``
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
- ``HTTPStreamingTransport``
- ``HTTPProgressTransport``
- ``URLSessionTransport``
- ``WebSocketTransport``
- ``WebSocketClient``
- ``WebSocketRequest``
- ``WebSocketConnection``
- ``WebSocketSession``
- ``WebSocketSessionConfiguration``
- ``WebSocketSessionEvent``
- ``URLSessionWebSocketTransport``
- ``RawResponse``
- ``HTTPStreamEvent``
- ``HTTPStreamResponse``
- ``ServerSentEvent``
- ``TransferProgress``
- ``TransferProgressKind``
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
- ``TracePropagationMiddleware``
- ``CacheMiddleware``
- ``LoggingMiddleware``
- ``CURLCommandStyle``
- ``CURLCommandBodyFormatting``
- ``CURLCommandOptions``
- ``NetworkEvent``
- ``TraceContext``
- ``RequestTrace``
- ``RequestCacheTraceEvent``
- ``RequestTraceAttempt``
- ``RequestTraceResult``
- ``NetworkActivityBufferingPolicy``
- ``RedactionPolicy``
