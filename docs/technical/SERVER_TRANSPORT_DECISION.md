# Server Transport Decision

Status: deferred for `0.3.0`.

## Decision

Comet will not add a server-side live transport dependency in `0.3.0`.

The core `HTTPTransport`, `HTTPStreamingTransport`, and `HTTPProgressTransport`
protocols remain server-capable extension points, but the shipped live
transports stay `URLSession`-backed for Apple-platform client apps.

## Rationale

- Adding `AsyncHTTPClient`, Vapor, or `FoundationNetworking` would change the
  dependency and CI story for every adopter.
- The current transport seams are enough for users to provide their own server
  adapter without waiting on package internals.
- Contract testing, generated clients, and trace propagation provide more value
  for `0.3.0` without expanding the supported runtime matrix.

## Compatibility

Generated request types and trace propagation are transport-agnostic. A future
server transport should preserve:

- `PreparedRequest` as the boundary object
- `RawResponse` as the transport result
- `TracePropagationMiddleware` behavior
- cache and retry middleware ordering

## Revisit Criteria

Revisit this after `0.3.0` when there is a concrete target runtime, CI platform,
and dependency decision for server-side Swift.
