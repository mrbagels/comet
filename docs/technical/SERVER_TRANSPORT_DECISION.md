# Server Transport Decision

Status: HTTP live transport shipped in `0.4.4`.

## Decision

Comet will support server-side live HTTP through the existing
`URLSessionTransport` instead of adding a new `AsyncHTTPClient`, Vapor, or
other runtime dependency.

The core `HTTPTransport`, `HTTPStreamingTransport`, and `HTTPProgressTransport`
protocols remain the extension points. `URLSessionTransport` now imports
`FoundationNetworking` where available, so server-side Swift can use the same
live HTTP transport that Apple-platform clients use. `URLSessionWebSocketTransport`
still depends on `URLSessionWebSocketTask`, which is Apple-platform only in this
package.

## Rationale

- Reusing `URLSessionTransport` adds no production package dependency and keeps
  existing client call sites unchanged.
- A focused Linux CI job can compile the core `Comet` target without requiring
  every optional integration product to support Linux in the first server pass.
- Server WebSocket support needs a separate dependency decision because the
  `URLSessionWebSocketTask` implementation is not portable through
  `FoundationNetworking`.

## Compatibility

Generated request types and trace propagation are transport-agnostic. The server
HTTP path preserves:

- `PreparedRequest` as the boundary object
- `RawResponse` as the transport result
- `TracePropagationMiddleware` behavior
- cache and retry middleware ordering

## Revisit Criteria

Revisit this when Comet needs incremental server-side streaming, server WebSocket
support, connection pooling controls beyond `URLSessionConfiguration`, or an
adapter for a specific server framework.
