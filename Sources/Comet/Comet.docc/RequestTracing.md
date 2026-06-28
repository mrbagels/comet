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

``HTTPClient/activity`` remains available for lightweight lifecycle events. Use traces when UI, logs, tests, or cassettes need a cohesive request timeline.
