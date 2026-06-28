# Streaming And Progress

Use streaming APIs when a response should be consumed over time instead of buffered into a single decoded value.

## Raw Stream Events

``HTTPClient/stream(_:chunkSize:)`` yields response metadata, byte chunks, and completion.

```swift
for try await event in client.stream(StreamEvents()) {
  switch event {
  case .response(let response):
    print(response.statusCode)
  case .bytes(let data):
    print(data.count)
  case .complete:
    break
  }
}
```

``URLSessionTransport`` supports true response streaming. Other transports can opt in with ``HTTPStreamingTransport``. Buffered transports fall back to one response event and one byte event.

Streaming requests run middleware preparation and terminal cleanup. Response
providers can satisfy a stream before the transport is opened, so fresh cached
responses from ``CacheMiddleware`` can stream from the cache. Live streaming
does not buffer the response body for response-mutating middleware.

## Lines And SSE

Use line streams for newline-delimited protocols.

```swift
for try await line in client.lines(StreamLogs()) {
  print(line)
}
```

Use Server-Sent Events for event feeds.

```swift
for try await event in client.serverSentEvents(StreamEvents()) {
  print(event.event as Any, event.data)
}
```

## Transfer Progress

Use the progress-aware raw send overload when a transport can report transfer progress.

```swift
let response = try await client.sendRaw(UploadAsset()) { progress in
  print(progress.kind, progress.fractionCompleted as Any)
}
```

Transports can provide exact progress by conforming to ``HTTPProgressTransport``. Basic transports report completed upload and download byte counts after buffering.
