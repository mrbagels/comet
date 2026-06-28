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

`returnCacheElseLoad` returns a fresh cached response when the entry is still
valid. If the entry is stale and has an `ETag` or `Last-Modified` validator,
``CacheMiddleware`` adds `If-None-Match` or `If-Modified-Since` before hitting
the transport. A `304 Not Modified` response is merged with the cached body and
refreshed headers.

Use the explicit strategies when the request needs a stricter contract:

- ``HTTPCachePolicy/cacheOnly`` returns a cached response or fails without
  touching the transport.
- ``HTTPCachePolicy/networkOnly`` bypasses reads and writes.
- ``HTTPCachePolicy/revalidate`` validates a cached response even when it is
  still fresh.
- ``HTTPCachePolicy/reloadIgnoringCache`` bypasses reads and stores the network
  replacement.

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

Completed ``RequestTrace`` values include cache events for hits, misses, bypasses, stale entries, revalidation attempts, `304` updates, stores, and skipped stores.

```swift
for await trace in client.traces {
  for event in trace.cacheEvents {
    print(event.kind, event.key, event.reason as Any)
  }
}
```

The current cache core is intentionally conservative. It keeps cache entries in a configured store and supports freshness metadata, validators, and `304 Not Modified` merging. Persistent stores, pruning, stale-if-error, and stale-while-revalidate are planned as separate patch milestones.
