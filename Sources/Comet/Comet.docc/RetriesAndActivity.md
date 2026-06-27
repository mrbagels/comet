# Retries And Activity

Use retry middleware, request metadata, and the activity stream to inspect request behavior.

## Configure Retry Behavior

``RetryMiddleware`` retries safe methods by default. Potentially unsafe writes need an idempotency key or an explicit ``RequestRetryPolicy``.

```swift
let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      RetryMiddleware(maxAttempts: 3),
      LoggingMiddleware(logLevel: .verbose)
    ]
  ),
  transport: URLSessionTransport()
)
```

## Add Request Metadata

```swift
struct RefreshFeed: APIRequest {
  let path: Path = "feed"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<[FeedItem]> = .json([FeedItem].self)

  var options: RequestOptions {
    RequestOptions(
      metadata: RequestMetadata(name: "RefreshFeed", tags: ["feed"]),
      retryPolicy: .automatic
    )
  }
}
```

## Observe Activity

Activity events expose direct diagnostic properties, so UI and logging code can inspect events without switching over every enum case.

```swift
Task {
  for await event in client.activity {
    print(event.kind)
    print(event.diagnosticSummary)
  }
}
```

Retry events include the request id, attempt number, retry delay, and metadata. Completed and failed events include duration.
