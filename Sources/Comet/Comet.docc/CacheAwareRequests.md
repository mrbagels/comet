# Cache-Aware Requests

Use ``CacheMiddleware`` when read requests should reuse process-local HTTP responses without changing request types or transports.

## Add A Cache Store

```swift
let cache = MemoryHTTPCacheStore()

let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      CacheMiddleware(store: cache)
    ]
  ),
  transport: URLSessionTransport()
)
```

Caching is disabled unless a request opts in with ``RequestOptions/cachePolicy``. The default policy for cache-aware reads is ``HTTPCachePolicy/returnCacheElseLoad``.

```swift
var options: RequestOptions {
  RequestOptions(cachePolicy: .returnCacheElseLoad)
}
```

Safe methods (`GET` and `HEAD`) can read and write cache entries automatically. Unsafe methods bypass the cache unless a policy explicitly allows them.

```swift
var options: RequestOptions {
  RequestOptions(
    cachePolicy: HTTPCachePolicy(
      strategy: .returnCacheElseLoad,
      allowsUnsafeMethods: true
    )
  )
}
```

## Inspect Cache Decisions

Completed ``RequestTrace`` values include cache events for hits, misses, bypasses, stores, and skipped stores.

```swift
for await trace in client.traces {
  for event in trace.cacheEvents {
    print(event.kind, event.key, event.reason as Any)
  }
}
```

The current cache core is intentionally conservative. It stores successful responses and returns them by method and URL. HTTP validator parsing, freshness, `304 Not Modified` merging, and persistent stores are planned as separate patch milestones.
