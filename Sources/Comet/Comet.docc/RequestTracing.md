# Request Tracing

Use ``HTTPClient/traces`` when request-level diagnostics should be grouped into a single completed record.

## Observe Traces

```swift
let task = Task {
  for await trace in client.traces {
    print(trace.diagnosticSummary)
  }
}
```

Each ``RequestTrace`` contains the request metadata, URL, method, total duration, final result, and ordered ``RequestTraceAttempt`` values. Retry middleware records retry delays on the attempt that triggered the retry.

```swift
for attempt in trace.attempts {
  print(attempt.number, attempt.responseStatusCode as Any, attempt.retryDelay as Any)
}
```

## Propagate Trace Headers

Add ``TracePropagationMiddleware`` when backend logs or gateway traces should share the same distributed trace ID as Comet diagnostics.

```swift
let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      TracePropagationMiddleware()
    ]
  ),
  transport: URLSessionTransport()
)
```

The middleware writes the W3C `traceparent` header. If a request already has a `traceparent` header, the middleware preserves it by default. If the request metadata provides a ``TraceContext``, that context is used. Otherwise Comet generates one from the request ID.

```swift
let traceContext = TraceContext(
  traceID: "4bf92f3577b34da6a3ce929d0e0e4736",
  parentID: "00f067aa0ba902b7",
  flags: "01"
)!

var options: RequestOptions {
  RequestOptions(
    metadata: RequestMetadata(
      name: "GetUser",
      operationID: "users.get",
      traceContext: traceContext
    )
  )
}
```

Completed ``RequestTrace`` values expose the propagated trace ID without storing arbitrary trace headers such as `tracestate`.

```swift
for await trace in client.traces {
  if let traceID = trace.traceID {
    backendLogger.correlate(traceID: traceID, operation: trace.metadata.operationName)
  }
}
```

``HTTPClient/activity`` remains available for lightweight lifecycle events. Use traces when UI, logs, tests, or cassettes need a cohesive request timeline.
