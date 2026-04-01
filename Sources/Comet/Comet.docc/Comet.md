# ``Comet``

Typed HTTP requests for modern Swift apps.

## Overview

Comet centers on three concepts:

- ``APIRequest`` models a typed request and response pair.
- ``HTTPClient`` executes requests with shared configuration and middleware.
- ``HTTPTransport`` performs the actual I/O, which keeps the core testable and replaceable.

The shipped live transport today is ``URLSessionTransport``, which makes Comet production-ready for Apple-platform client apps. The transport seam is intentionally open so the same request model can also power mocks, recorders, replayers, and future non-`URLSession` transports.

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
- ``RawResponse``
- ``NetworkError``

### Middleware And Activity

- ``Middleware``
- ``BearerTokenMiddleware``
- ``RetryMiddleware``
- ``LoggingMiddleware``
- ``NetworkEvent``
