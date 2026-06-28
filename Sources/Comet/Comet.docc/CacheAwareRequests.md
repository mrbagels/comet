# Cache-Aware Requests

Use ``CacheMiddleware`` when read requests should reuse HTTP responses without changing request types or transports.

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

``MemoryHTTPCacheStore`` is the lightest option for tests, previews, and
process-local reads. Use ``FileHTTPCacheStore`` when cached responses should
survive app launches:

```swift
let cache = FileHTTPCacheStore(
  namespace: "api-v1",
  maximumSizeBytes: 25 * 1024 * 1024
)
```

The file store writes JSON entries under
``FileHTTPCacheStoreConfiguration/resolvedDirectoryURL``, isolates entries by
namespace, prunes oldest entries when the configured size limit is exceeded, and
removes corrupted entries when they are encountered.

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
- ``HTTPCachePolicy/staleWhileRevalidate`` returns a stale cached response
  immediately and schedules one background refresh for that cache key.
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

For offline-tolerant reads, enable stale fallback explicitly. When a stale cached
response exists and the network request fails, ``CacheMiddleware`` returns the
stale response and records a cache hit with
``RequestCacheTraceEvent/Reason/staleIfError``.

```swift
var options: RequestOptions {
  RequestOptions(
    cachePolicy: HTTPCachePolicy(
      strategy: .returnCacheElseLoad,
      allowsStaleIfError: true
    )
  )
}
```

Use stale-while-revalidate when UI should keep showing the last cached value
while Comet refreshes the store in the background:

```swift
var options: RequestOptions {
  RequestOptions(cachePolicy: .staleWhileRevalidate)
}
```

The foreground request records stale, hit, refresh, and skipped-store cache
events. The background refresh uses validators when the cached entry has an
`ETag` or `Last-Modified`, merges `304 Not Modified` responses into the stored
entry, emits its own lifecycle activity and completed trace, and coalesces
concurrent refreshes for the same cache key. Entries marked `no-store`,
`no-cache`, `must-revalidate`, or shared-cache `proxy-revalidate` fall back to
synchronous revalidation instead of serving stale data.

Freshness is conservative by default. Cached responses must declare explicit
freshness with `Cache-Control` or `Expires`, include validators for
revalidation, or use a policy-level default freshness lifetime. `Age`,
`s-maxage`, `must-revalidate`, `stale-if-error`, shared-cache `private`, and
`Vary` headers are honored when deciding whether an entry can be reused.

```swift
var options: RequestOptions {
  RequestOptions(
    cachePolicy: HTTPCachePolicy(
      strategy: .returnCacheElseLoad,
      defaultFreshnessLifetime: .seconds(30)
    )
  )
}
```

## Inspect Cache Decisions

Completed ``RequestTrace`` values include cache events for hits, misses, bypasses, stale entries, revalidation attempts, stale-while-revalidate refresh scheduling, stale fallbacks, `304` updates, stores, and skipped stores. Stale-while-revalidate background refreshes emit a separate completed trace with the refresh attempt result and any cache update events.

```swift
for await trace in client.traces {
  for event in trace.cacheEvents {
    print(event.kind, event.key, event.reason as Any)
  }
}
```

The current cache core is intentionally conservative. It keeps cache entries in a
configured memory or file store and supports freshness metadata, validators,
`304 Not Modified` merging, size pruning, stale-if-error fallback, and
stale-while-revalidate background refreshes.
