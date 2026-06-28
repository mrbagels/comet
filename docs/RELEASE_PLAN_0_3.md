# Comet 0.3.0 Release Plan

This plan captured the post-`0.2.0` V3 roadmap and the bundled release train
that shipped as `0.3.0`. It remains as release history for the cache, contract,
generator, trace-propagation, and server-direction work.

## North Star

`0.3.0` makes Comet feel more like a production networking workflow platform,
not only a typed request executor. The completed release gives users:

- cache-aware reads with HTTP revalidation semantics
- deterministic contract testing over the transport and cassette model
- a mock-server workflow for demos and tests
- generated request types from a focused OpenAPI subset
- distributed trace propagation that connects client logs, traces, and servers
- a credible server-side transport direction with a documented support boundary
- updated playground scenarios, DocC articles, README examples, and CI gates

## Release Principles

- Keep every release addition additive unless we explicitly decide a minor-version
  break is worth it for `0.3.0`.
- Prefer small public protocols and concrete defaults over one large system type.
- Preserve the current transport seam. New behavior should layer through
  `HTTPTransport`, middleware, `RequestOptions`, traces, or `CometTesting`.
- Do not add production dependencies without a deliberate dependency decision.
- The final bundle gets package tests, API-diff gate, playground smoke coverage,
  changelog entries, and docs updates.
- If a milestone proves too large, split the implementation but do not skip the
  release-quality gate.

## Bundled Release Train

### 0.2.1: Release Rails And V3 Planning

Purpose: make the release train explicit and reduce friction before larger
features start landing.

Status: completed in `0.3.0` with plan artifacts, a fresh-client smoke
script, and a direct `HTTPTypes` dependency for the playground test target.

Deliverables:

- Add this `0.3.0` milestone plan in Markdown and static HTML.
- Update the product roadmap to point at the executable release train.
- Add changelog coverage for the plan artifact.
- Add or document a fresh-client smoke command that validates package adoption
  from outside this repository.
- Investigate the iOS project dependency-scan warning for `Comet` and
  `HTTPTypes`; fix it if the generated project needs a dependency tweak.

Acceptance:

- `swift test --disable-xctest`
- `.github/scripts/check-api-breaking-changes.sh v0.3.0`
- iOS playground smoke tests when project files change
- docs typography and stale-wording scans

### 0.2.2: Distributed Trace Propagation

Purpose: make Comet traces useful across process boundaries before cache and
contract systems add more diagnostic surface.

Status: completed in `0.3.0` with W3C trace context parsing, propagation
middleware, trace IDs on completed request traces, DocC examples, and a mock
playground proof that echoes the outbound `traceparent` header.

Deliverables:

- Add a `TraceContext` value with W3C `traceparent` support.
- Add `TracePropagationMiddleware` that injects trace headers.
- Add request metadata hooks for operation names and trace IDs.
- Record propagated trace IDs on `RequestTrace` without leaking sensitive data.
- Add DocC examples for connecting Comet traces to backend logs.
- Add playground trace examples that show outbound trace headers.

Acceptance:

- Unit tests for parse, render, invalid input, middleware injection, and
  redaction behavior.
- API-diff gate passes against the latest release tag.
- Playground trace timeline still passes smoke tests.

### 0.2.3: Cache Core

Purpose: establish the smallest cache system that can serve real app reads
without taking on full persistence or revalidation yet.

Status: completed in `0.3.0` with opt-in cache policy controls, cache
keys, cached response values, a memory cache store, cache middleware, cache
trace events, README and DocC coverage, and tests for safe-method caching and
unsafe-method bypass.

Deliverables:

- Add `HTTPCachePolicy`, `HTTPCacheKey`, `CachedHTTPResponse`, and
  `HTTPCacheStore` protocols.
- Add an actor-backed `MemoryHTTPCacheStore`.
- Add `CacheMiddleware` for cache lookup and response storage.
- Add request-level cache controls through `RequestOptions`.
- Record cache hit, miss, bypass, and store decisions in `RequestTrace`.
- Add focused tests for safe-method caching and write-request bypass.

Acceptance:

- Cache behavior is opt-in and conservative by default.
- Unsafe methods do not read or write cache unless explicitly allowed.
- Existing retry, auth, deduplication, and typed-error tests still pass.

### 0.2.4: HTTP Revalidation

Purpose: make cached reads respect HTTP validators and standard freshness
metadata.

Status: completed in `0.3.0` with typed cache metadata, conditional
request headers, `304 Not Modified` merge behavior, explicit cache-only,
network-only, return-cache-else-load, reload-ignoring-cache, and revalidate
policies, plus trace coverage for stale and revalidation decisions.

Deliverables:

- Parse `Cache-Control`, `Expires`, `ETag`, and `Last-Modified` response
  headers into typed cache metadata.
- Add conditional request support with `If-None-Match` and
  `If-Modified-Since`.
- Merge `304 Not Modified` responses with cached bodies and refreshed headers.
- Support explicit request policies such as network-only, cache-only,
  return-cache-else-load, and revalidate.
- Add traces and activity summaries for revalidation decisions.

Acceptance:

- Tests cover fresh hit, stale revalidation, `304` merge, `200` replacement,
  expired entry, and cache bypass.
- Public examples show the intended request-level API.
- API-diff gate passes against latest release tag.

### 0.2.5: Persistent Cache And Playground Cache Lab

Purpose: make the cache useful beyond a single process and make the behavior
inspectable.

Status: completed in `0.3.0` with a file-backed store, namespace
configuration, size pruning, corrupted-entry cleanup, stale-if-error fallback,
and a deterministic playground cache lab covering first load, fresh hit, stale
revalidation, offline stale fallback, and clear cache.

Deliverables:

- Add a file-backed cache store for Apple platforms.
- Add size limits, entry pruning, and cache namespace configuration.
- Add stale-if-error fallback.
- Add cache scenarios to the playground: first load, fresh hit, stale
  revalidation, offline stale fallback, and clear cache.
- Add DocC article: cache-aware requests and revalidation.
- Defer stale-while-revalidate until the background refresh semantics can be
  modeled without surprising request traces.

Acceptance:

- Tests cover file persistence, pruning, corrupted entry handling, and cleanup.
- Playground smoke tests cover at least one deterministic cache scenario.
- Docs explain when to choose memory cache versus file cache.

### 0.2.6: Contract Testing Foundation

Purpose: turn the existing mock and cassette tools into a strict request/response
contract workflow.

Status: completed in `0.3.0` with strict expectations, contract
transports, JSON reports, cassette conversion, and focused tests.

Deliverables:

- Add `ContractExpectation`, `ContractMatch`, `ContractViolation`, and
  `ContractReport` types in `CometTesting`.
- Add a `ContractTransport` that validates method, path, query, headers, body,
  and declared metadata.
- Add cassette-to-contract conversion for recorded fixtures.
- Add unused-expectation and unexpected-request failures.
- Add JSON contract report export for CI artifacts.

Acceptance:

- Tests cover exact match, flexible header matching, body mismatch, unexpected
  request, and unused expectation reporting.
- Contract failures include enough context to fix the request type quickly.
- Existing `MockTransport`, `RecordingTransport`, and `ReplayTransport` behavior
  remains source compatible.

### 0.2.7: Mock Server Workflow

Purpose: provide a higher-level workflow for app demos and UI tests that need a
local backend shape without a real backend.

Status: completed in `0.3.0` with a transport-level `MockServer` facade
over contract expectations and a deterministic playground contract-server demo.

Deliverables:

- Add a `MockServer` facade over contract expectations and cassette fixtures.
- Provide fixture registration by `APIRequest` type where possible.
- Support deterministic latency, failures, and ordered scenarios.
- Add playground demos that switch between mock server scenarios.
- Decide whether a real local HTTP listener belongs in `CometTesting` or should
  wait for a separate server-transport product.

Acceptance:

- UI/demo flows can run against the same scenario definitions used by package
  tests.
- Scenario failures produce contract reports.
- If a real HTTP listener is deferred, the docs state the boundary clearly.

### 0.2.8: OpenAPI Generator

Purpose: prove generated Comet clients without trying to cover every OpenAPI
feature in one pass.

Status: completed in `0.3.0` with a JSON/YAML OpenAPI generator core,
`comet-openapi-generate` executable, request generation for
parameters, component schema models, local schema `$ref`s, JSON bodies,
metadata, typed success serializers, typed error hooks, and snapshot tests.

Deliverables:

- Add an executable or SwiftPM command plugin for generation.
- Support JSON and YAML OpenAPI 3.0 or 3.1 documents.
- Generate request types for paths, methods, path parameters, query parameters,
  headers, JSON bodies, operation metadata, success responses, and typed error
  responses.
- Add fixture specs and generated-output snapshot tests.
- Add docs showing generated files plus manual customization boundaries.

Dependency decision:

- YAML support, JSON Schema depth, and formatter integration may require new
  dependencies. Choose those explicitly before implementation.

Acceptance:

- The generated code compiles in an example client target.
- Generated request types use existing Comet primitives rather than bespoke
  runtime abstractions.
- Unsupported OpenAPI features fail with actionable diagnostics.

### 0.2.9: Server Direction, Reachability, And TCA Ergonomics

Purpose: close the remaining V3 roadmap items enough to either ship them in
`0.3.0` or explicitly defer them with evidence.

Status: completed in `0.3.0` with a server transport decision record,
transport-agnostic compatibility notes, reachability hint primitives, and a
small `CometTCA` request-state helper.

Deliverables:

- Add a server-side transport decision record:
  `AsyncHTTPClient` adapter, `FoundationNetworking` adapter, separate product,
  or deferred.
- If approved, add a minimal server transport product behind a focused target.
- Add trace propagation compatibility for the server transport.
- Add reachability primitives if they can be implemented without platform
  awkwardness or misleading guarantees.
- Add small `CometTCA` request-state helpers only if they stay generic and do
  not pull app-domain assumptions into the package.
- Add fresh-client integration smoke coverage for the selected products.

Acceptance:

- Server support has a clear platform statement and CI story.
- Reachability docs explain that it is a hint, not a correctness boundary.
- TCA additions are optional, source compatible, and covered by tests.

### 0.3.0: Stabilization And Release Cut

Purpose: promote the accumulated V3 work into a coherent minor release.

Deliverables:

- Full public API naming review across V3 additions.
- Migration notes from `0.2.x` to `0.3.0`.
- README refresh with cache, contracts, generator, and trace propagation
  examples.
- DocC navigation update for all new tutorials.
- Changelog rollup for the `0.3.0` release.
- Playground smoke tests covering the new diagnostic surfaces.
- API diff reviewed against `v0.2.0`, patch tags, and the final `v0.3.0` tag.
- GitHub Release notes.

Acceptance:

- `swift test --disable-xctest`
- `.github/scripts/check-api-breaking-changes.sh latest`
- iOS playground smoke tests
- fresh-client smoke test
- docs typography and stale-wording scans
- CI green on `next`, promotion to `master`, tag `v0.3.0`

## Workstream Map

| Workstream | Primary Milestones | Main Package Area |
| --- | --- | --- |
| Observability | `0.2.2`, `0.3.0` | `Comet/Observability`, middleware, DocC |
| Caching | `0.2.3`, `0.2.4`, `0.2.5` | `Comet/Cache`, `RequestOptions`, traces |
| Contract testing | `0.2.6`, `0.2.7` | `CometTesting`, cassettes, playground |
| Code generation | `0.2.8` | new generator target or plugin |
| Server story | `0.2.9` | new optional target, architecture docs |
| Integration polish | every patch | CI, README, DocC, playground |

## Decisions Made

- File cache storage stays plain file-backed storage with user-owned file
  protection and app-level encryption decisions.
- `MockServer` remains transport-level for `0.3.0`; a real local HTTP listener
  is deferred.
- OpenAPI generation supports JSON directly and YAML through Yams. Full JSON
  Schema coverage, formatting integration, and a SwiftPM command plugin can be
  revisited after the CLI proves useful.
- Server-side live transports are deferred for `0.3.0`; see
  [Server Transport Decision](technical/SERVER_TRANSPORT_DECISION.md).

## Default Verification Per Patch

Run the narrowest useful command while developing, then finish each patch with:

```sh
swift test --disable-xctest
.github/scripts/check-api-breaking-changes.sh <latest-tag>
```

When playground, docs navigation, project generation, or user-facing workflows
change, also run the iOS playground smoke tests through XcodeBuildMCP or:

```sh
cd Examples/CometPlayground
xcodegen generate
SIMULATOR_ID="$(../../.github/scripts/select-ios-simulator.sh)"
xcodebuild test \
  -project CometPlayground.xcodeproj \
  -scheme CometPlaygroundApp \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO
```

Docs patches should additionally run:

```sh
rg -n $'\u2014|\u2013|[\u201c\u201d]' README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md docs Resources Examples/CometPlayground/README.md Sources/Comet/Comet.docc .github/pull_request_template.md
```

## Release Cadence

- Land one milestone as a focused batch of commits on `next`.
- Push and wait for CI.
- Tag a patch release when the milestone is user-visible and release-worthy.
- Keep `CHANGELOG.md` current during the milestone, not after it.
- If a milestone spills, tag the completed vertical slice and carry the rest to
  the next patch rather than blocking the train.
