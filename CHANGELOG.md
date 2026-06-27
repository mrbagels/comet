# Changelog

All notable changes to Comet are documented here.

Comet is still pre-1.0. The `0.1.x` line is the public-prep patch line while
the larger structure and API refactor continues. `0.2.0` is reserved for the
completed v2 foundation.

## 0.1.2 - 2026-06-27

### Added

- First-party SVG brand assets under `Resources/Brand`.
- Playground app asset catalog support for the Comet gradient icon.

### Changed

- Reworked the README with the Comet mark, release badges, clearer package positioning, and updated installation instructions.
- Added brand polish to the playground README and home screen.

## 0.1.1 - 2026-06-27

### Added

- WebSocket client, transport, request, connection, and mock transport support.
- Request activity events with configurable buffering.
- Cassette recording and replay fixtures in `CometTesting`.
- Request metadata for logs, activity events, and future traces.
- Shared redaction policy for logging, cURL output, and cassette recording.
- Status validation presets for not-modified, redirect, and no-content workflows.
- Public repository metadata: license, contribution guide, security policy, and changelog.
- CI guardrails for secret scanning and public API diff reporting.

### Changed

- Clarified the Swift 6.2, iOS 18, macOS 15, and visionOS 2 support policy.
- Tightened intentionally public API surface around internal activity broadcasting and request deduplication.
- `RetryMiddleware` now uses conservative retry safety by default: safe methods retry automatically, while write requests require an idempotency key or explicit request retry policy.
- cURL generation now shell-quotes arguments and uses the shared redaction policy.

### Security

- Cassette recording now redacts sensitive HTTP headers by default and supports request/response body redaction hooks.

## 0.2.0 - Unreleased

### Planned

- Continue the larger v2 restructuring around typed errors, structured traces, richer diagnostics, generated-client workflows, and the playground diagnostics lab.

## 0.1.0 - 2026-04-01

### Added

- Initial release baseline for typed HTTP requests, response serializers, middleware, retry behavior, deduplication, activity events, testing transports, and TCA integration.
