# Comet Product Roadmap

This roadmap captures the selected product direction after the public-readiness pass. It is intentionally broader than a single release plan: listing an item here means it is in scope for exploration and sequencing, not that it must ship immediately.

## Product Direction

Comet should become a highly ergonomic Swift networking foundation with first-class debugging, testing, replay, realtime, and generated-client workflows. The package should stay small at the core, but the surrounding ecosystem should make production networking less repetitive, safer by default, and easier to understand.

The selected roadmap has five themes:

- **Ergonomics:** request definitions should be concise, discoverable, and hard to misuse.
- **Safety:** retries, auth, logging, and cassettes should avoid common production footguns.
- **Observability:** request behavior should be easy to inspect through logs, traces, cURL, and the playground.
- **Capability:** support streaming, transfer progress, caching, authentication, and resilient WebSockets.
- **Workflow:** improve release gates, API stability, contract testing, generated clients, and the playground demo lab.

## Selected Minor Features And Improvements

### M1. Typed API Error Decoding

Add request-level support for decoding structured error bodies.

Status: initial typed error surface completed in the `0.1.x` patch line with `ErrorResponseSerializer`, `APIRequestWithErrorResponse`, and `APIClientError`.

Technical shape:

- Add an error serializer concept, probably in `RequestOptions` or a companion request protocol.
- Preserve raw `NetworkError.http` information while making decoded domain errors available.
- Avoid forcing all requests into one global error model.

User experience:

- A request can declare how successful responses and error responses decode.
- Call sites can switch on a typed domain error instead of manually parsing `NetworkError.bodyData`.

Value:

- Reduces boilerplate in every API integration.
- Makes UI error presentation cleaner and more consistent.

Dependencies:

- Benefits from M3 request metadata and A6 request traces.
- Helps A4 authentication and A12 playground failure demos.

### M2. Safer cURL Generation

Make generated cURL commands pasteable and shell-safe.

Technical shape:

- Escape headers, URLs, and bodies safely.
- Support pretty multiline JSON when useful.
- Integrate with the shared redaction policy from M7.

User experience:

- Developers copy logged cURL output and reproduce requests reliably.
- Sensitive values stay redacted in logs and screenshots.

Value:

- High-impact debugging improvement with relatively small scope.

Dependencies:

- Should share M7 redaction policy.
- Feeds A6 request traces and A12 playground request inspectors.

### M3. Request Names, Tags, And Metadata

Allow requests to carry human-readable metadata.

Technical shape:

- Extend `RequestOptions` with fields such as `name`, `tags`, and maybe `operationID`.
- Include metadata in events, traces, logs, cassettes, and playground display.

User experience:

- Activity views show `GetUser` or `CreateSession` instead of only method and URL.
- Filtering by feature or category becomes possible.

Value:

- Makes observability and demos much easier to understand.

Dependencies:

- Enables M10 activity details and A6 structured traces.
- Aligns naturally with A5 OpenAPI operation IDs.

### M4. Query Item Builder Ergonomics

Improve common query construction patterns.

Technical shape:

- Add optional item helpers.
- Add bool, numeric, date, and collection encoding helpers.
- Keep current `QueryItem` simple, but add ergonomic factory APIs.

User experience:

- Request definitions avoid repetitive `if let` and manual string conversion.

Value:

- Small API polish that improves every request definition.

Dependencies:

- Useful for A5 OpenAPI code generation.

### M5. Status Validation Presets

Add common status validation presets.

Technical shape:

- Add presets such as `.successOrNotModified`, `.successAndRedirects`, and `.noContent`.
- Keep `.custom` for advanced cases.

User experience:

- Developers discover common HTTP cases without writing custom ranges.

Value:

- Improves clarity and reduces small mistakes.

Dependencies:

- Supports A3 caching and revalidation.

### M6. Retry Safety Defaults

Make retry behavior safe by default.

Technical shape:

- Have retry middleware account for HTTP method, request body, idempotency key, and explicit retry policy.
- Retry safe methods by default.
- Require opt-in for potentially unsafe writes unless an idempotency key or explicit policy is present.

User experience:

- Developers get sensible retry behavior without accidentally duplicating writes.

Value:

- Important production safety improvement.

Dependencies:

- Supports A4 authentication replay and A7 WebSocket reconnection policy reuse.

### M7. Shared Redaction Policy

Unify sensitive-data redaction across logging, cURL, traces, and cassettes.

Technical shape:

- Promote a core redaction type in `Comet`.
- Use it from `LoggingMiddleware`, `PreparedRequest.curlCommand`, `RecordingTransport`, and future traces.
- Support header and body redaction.

User experience:

- One policy controls what is safe to show or persist.

Value:

- Makes debugging safer and the package easier to trust.

Dependencies:

- Builds on the public-readiness redaction work in `CometTesting`.
- Enables M2, A6, A8, and A12.

### M8. DocC Workflow Tutorials

Add workflow-first documentation.

Technical shape:

- Add tutorials for authenticated JSON, typed errors, retries, testing, cassettes, WebSockets, and TCA.
- Keep README concise and let DocC hold deeper walkthroughs.

User experience:

- New users can follow real workflows instead of assembling behavior from symbol docs.

Value:

- Major adoption and onboarding improvement.

Dependencies:

- Should be updated alongside each feature release.

### M9. Playground Failure Gallery

Add realistic failure and recovery scenarios to the iOS playground.

Technical shape:

- Add mock scenarios for timeout, 401, 429 retry, 500, malformed JSON, cancelled request, and WebSocket close.
- Surface expected behavior and activity output.

User experience:

- Users can see how Comet behaves when things go wrong.

Value:

- Makes the example app a stronger teaching and regression surface.

Dependencies:

- Benefits from M1 typed errors, M10 activity details, and A6 traces.

### M10. Richer Activity Event Details

Make activity events more useful without requiring external correlation.

Technical shape:

- Add request metadata, method, URL, status, attempt, retry delay, and possibly response byte counts.
- Consider moving toward A6 `RequestTrace` instead of expanding event cases indefinitely.

User experience:

- Debug UIs and logs have enough information to answer what happened.

Value:

- Improves supportability and playground quality.

Dependencies:

- Should be designed with A6 structured traces.

## Selected Major Features, Systems, And Refactors

### A1. Streaming, SSE, And AsyncSequence Responses

Add first-class streaming APIs.

Technical shape:

- Introduce streaming transport capabilities without bloating basic `HTTPTransport`.
- Add `HTTPClient.stream` APIs returning `AsyncSequence` values.
- Support raw byte streams, line streams, and SSE event streams.

User experience:

- Developers can build chat, event feeds, and long-running task UIs using `for await`.

Value:

- Expands Comet beyond classic request/response.

Dependencies:

- Needs cancellation behavior and A6 tracing to be carefully designed.

### A2. Upload And Download Progress

Support file transfers and progress reporting.

Technical shape:

- Add specialized upload/download APIs or a transfer transport protocol.
- Represent progress as `AsyncSequence` events.
- Support destination URLs, temporary files, cancellation, and cleanup.

User experience:

- Apps can show progress bars and handle large payloads without custom transport code.

Value:

- Common production requirement and a clear capability expansion.

Dependencies:

- Aligns with A1 streaming and A6 traces.

### A3. Caching And Revalidation

Add cache helpers around HTTP semantics.

Technical shape:

- Add cache store protocol and middleware.
- Support ETag, Last-Modified, 304 handling, stale-while-revalidate, and cache policy options.

User experience:

- Developers can make fast, offline-tolerant reads with less custom code.

Value:

- Raises Comet from request executor to application networking foundation.

Dependencies:

- Uses M5 status presets and M3 request metadata.

### A4. Authentication System

Provide robust token refresh and 401 replay workflows.

Technical shape:

- Add auth coordinator actor for token reads, refresh de-duplication, and request replay.
- Redact auth fields through M7.
- Respect M6 retry safety.

User experience:

- Apps can configure auth once instead of hand-rolling refresh races.

Value:

- High-value production feature because auth is a common source of bugs.

Dependencies:

- Requires M6 retry safety and M7 redaction.

### A5. OpenAPI Code Generation

Generate Comet request types from API specs.

Technical shape:

- Build a SwiftPM plugin or CLI.
- Generate `APIRequest` types, paths, query items, bodies, response serializers, and operation metadata.
- Support incremental/manual customization.

User experience:

- Developers get typed clients from backend contracts.

Value:

- Transformational for adoption and larger codebases.

Dependencies:

- Benefits from M3 request metadata, M4 query helpers, and M1 typed errors.

### A6. Structured Request Trace System

Replace loose activity events with request-level traces.

Technical shape:

- Introduce `RequestTrace` with request metadata, attempts, timings, middleware effects, retry history, bytes, and result.
- Keep `client.activity` as a stream, but make the payload richer and cohesive.
- Apply M7 redaction consistently.

User experience:

- Developers see a clear timeline for each request.

Value:

- Central infrastructure for debugging, playground, tests, and future observability.

Dependencies:

- Depends on M3 and M7.
- Enables A12 demo lab and improves A8 contract testing diagnostics.

### A7. Resilient WebSocket Sessions

Add reconnection, keepalive, and `AsyncSequence` message consumption.

Technical shape:

- Add `WebSocketSession` over low-level `WebSocketConnection`.
- Support `messages`, ping/pong keepalive, retry/backoff reconnect, and close policies.

User experience:

- Developers consume socket messages with `for await` and configure resilience declaratively.

Value:

- Makes WebSocket support practical for real apps.

Dependencies:

- Reuses M6 retry/backoff thinking and A6 traces.

### A8. Mock Server And Contract Testing

Turn requests/cassettes into local contract testing workflows.

Technical shape:

- Serve recorded cassettes or registered `APIRequest` fixtures from a local mock server.
- Validate that app requests match expected method/path/query/body shapes.
- Optionally emit contract reports.

User experience:

- UI tests and manual demos run without a real backend.

Value:

- Strong testing and workflow differentiator.

Dependencies:

- Builds on cassette model, M7 redaction, and A6 traces.

### A10. API Stability Gate

Make API breakage explicit in CI and release workflow.

Technical shape:

- Convert the current API-diff reporting job into a policy gate.
- Require changelog/version acknowledgement for detected breaks.
- Potentially require PR labels such as `api-breaking`, `api-additive`, or `api-internal`.

User experience:

- Maintainers see release impact before merge.

Value:

- Protects package trust as the public API grows.

Dependencies:

- Complements release automation and changelog discipline.

### A12. Playground Demo Lab

Evolve the example app into an interactive documentation and verification surface.

Technical shape:

- Add request inspector, response viewer, trace timeline, cassette viewer, failure gallery, socket monitor, and copy-cURL actions.
- Keep mock/live mode switching.

User experience:

- Users learn Comet by running scenarios and inspecting exactly what happened.

Value:

- A polished demo lab can materially improve adoption and confidence.

Dependencies:

- Strongly depends on M2, M3, M9, M10, A6, and A7.

## Proposed Release Slices

### Slice 1: Debugging And Safety Foundation

Goal: make existing request/response behavior safer and easier to inspect.

Includes:

- M2 safer cURL generation
- M3 request metadata
- M5 status validation presets
- M6 retry safety defaults
- M7 shared redaction policy
- M10 richer activity details, limited to current event model
- A10 stronger API stability gate

Why first:

- These changes are foundational and improve nearly every later feature.
- They are high ROI and keep scope bounded.

### Slice 2: Documentation And Playground Teaching Surface

Goal: make Comet easier to understand and evaluate.

Includes:

- M8 DocC tutorials
- M9 playground failure gallery
- First phase of A12 playground demo lab

Why second:

- It converts internal capabilities into a clear product experience.
- It creates visible regression coverage for future features.

### Slice 3: Typed Errors And Authentication

Goal: improve common production API workflows.

Includes:

- M1 typed API error decoding
- A4 authentication system

Why third:

- Auth and error presentation are tightly related in real apps.
- Both depend on redaction, retry safety, metadata, and traces.

### Slice 4: Structured Tracing

Goal: make request behavior first-class and inspectable.

Includes:

- A6 structured request traces
- Deeper A12 trace timeline integration

Why fourth:

- Traces become the shared model for streaming, transfers, sockets, caching, and mock-server diagnostics.

### Slice 5: Streaming And Transfers

Goal: expand Comet beyond simple request/response.

Includes:

- A1 streaming, SSE, and `AsyncSequence` responses
- A2 upload and download progress

Why fifth:

- Both require careful transport design and cancellation semantics.

### Slice 6: Caching And Revalidation

Goal: support fast, resilient read workflows.

Includes:

- A3 caching and revalidation

Why sixth:

- Caching depends on status validation, metadata, and trace visibility.

### Slice 7: Resilient WebSockets

Goal: make realtime support production-oriented.

Includes:

- A7 resilient WebSocket sessions
- A12 socket monitor integration

Why seventh:

- Uses retry/backoff and tracing lessons from earlier slices.

### Slice 8: Contract Testing And Generated Clients

Goal: support larger teams and backend-contract workflows.

Includes:

- A8 mock server and contract testing
- A5 OpenAPI code generation

Why last:

- These benefit heavily from mature request metadata, typed errors, query helpers, traces, cassettes, and playground inspection tools.

## Highest-ROI Initial Backlog

1. Shared redaction policy across `Comet` and `CometTesting`. Completed in the `0.1.x` patch line.
2. Safe, pasteable cURL generation. Shell-safe output, compact or multiline formatting, and pretty JSON body output completed in the `0.1.x` patch line.
3. Request metadata in options and activity events. Completed in the `0.1.x` patch line.
4. Status validation presets. Completed in the `0.1.x` patch line.
5. Retry safety defaults. Completed in the `0.1.x` patch line.
6. Richer activity event payloads. Initial diagnostic properties completed in the `0.1.x` patch line.
7. Query item builder ergonomics. Initial optional, boolean, collection, joined, and date helpers completed in the `0.1.x` patch line.
8. Playground failure gallery.
9. DocC tutorials for core workflows.
10. Typed API error decoding. Initial request-level and call-site decoding completed in the `0.1.x` patch line.
11. API stability gate policy.

## Open Design Questions

- Should typed errors live on `APIRequest`, in `RequestOptions`, or in a separate protocol?
- Should streaming extend `HTTPTransport`, or should Comet introduce a separate streaming transport protocol?
- Should traces replace `NetworkEvent`, wrap it, or live beside it?
- How much auth policy should Comet own versus leaving auth fully middleware-based?
- Should OpenAPI generation be a SwiftPM plugin, standalone CLI, or both?
- Should the playground remain iOS-only, or should it eventually become a macOS or web documentation companion too?
