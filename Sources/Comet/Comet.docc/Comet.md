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

### Essentials

- ``APIRequest``
- ``HTTPClient``
- ``ClientConfiguration``
- ``RequestOptions``
- ``ResponseSerializer``
- ``HTTPBody``
- ``Path``

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

### Middleware And Activity

- ``Middleware``
- ``BearerTokenMiddleware``
- ``RetryMiddleware``
- ``LoggingMiddleware``
- ``NetworkEvent``
