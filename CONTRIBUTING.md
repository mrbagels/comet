# Contributing

Comet is early and deliberately easy to contribute to. Small fixes, docs edits, examples, tests, and design feedback are welcome.

## Quick Start

1. Branch from `next`.
2. Make the smallest useful change.
3. Add or update focused tests when behavior changes.
4. Open a pull request with a short summary and the checks you ran.

Draft pull requests are fine. It is also fine to open an issue or discussion before coding if the design is unclear.

## Local Checks

For most code changes, run:

```sh
swift test
```

If you touch the example app or platform integration, also run:

```sh
cd Examples/CometPlayground
xcodegen generate
xcodebuild test -project CometPlayground.xcodeproj -scheme CometPlaygroundApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'
```

If you change public API, run:

```sh
swift package diagnose-api-breaking-changes v0.1.0
```

Expected public API movement should be mentioned in `CHANGELOG.md`.

## Style

- Prefer clear, small APIs over clever abstractions.
- Keep production code in `Comet`, test helpers in `CometTesting`, and TCA-specific helpers in `CometTCA`.
- Add examples or DocC notes when a feature would be hard to discover from the symbol name alone.
- Keep generated fixtures and recordings free of private data.

## Secrets And Fixtures

`RecordingTransport` can record URLs, headers, bodies, cookies, and auth values. Use `RecordingRedaction` or `RedactionPolicy` before committing fixtures, and review generated cassette JSON before opening a pull request.

Do not commit `.env` files, credentials, private keys, production data, or unredacted customer payloads.
