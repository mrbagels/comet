# Authenticated JSON Requests

Build a typed request, attach authentication middleware, and decode JSON through the shared client configuration.

## Define The Response

Keep response models `Sendable` so they can safely cross async boundaries.

```swift
struct User: Decodable, Sendable {
  let id: Int
  let name: String
}
```

## Define The Request

An ``APIRequest`` declares the path, method, and response serializer. Add ``RequestMetadata`` when you want logs and activity events to show a human-readable name.

```swift
struct GetUser: APIRequest {
  let userID: Int

  var path: Path { "users" / userID }
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<User> = .json(User.self)

  var options: RequestOptions {
    RequestOptions(
      apiVersion: "v1",
      metadata: RequestMetadata(name: "GetUser", tags: ["users"])
    )
  }
}
```

## Configure The Client

Use ``BearerTokenMiddleware`` when an access token is available asynchronously and no refresh workflow is needed. The middleware skips the header when the provider returns `nil`.

```swift
let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      BearerTokenMiddleware {
        await authStore.accessToken
      }
    ]
  ),
  transport: URLSessionTransport()
)
```

Use ``AuthenticationMiddleware`` when the app needs token refresh and safe 401 replay. The coordinator de-duplicates concurrent refreshes, and the middleware only replays requests allowed by ``RequestRetryPolicy``.

```swift
let auth = AuthenticationCoordinator.bearer(
  token: {
    await authStore.accessToken
  },
  refresh: {
    try await authStore.refreshAccessToken()
  }
)

let client = HTTPClient.live(
  configuration: ClientConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    middleware: [
      AuthenticationMiddleware(coordinator: auth)
    ]
  ),
  transport: URLSessionTransport()
)
```

## Send The Request

```swift
let user = try await client.send(GetUser(userID: 42))
```

`HTTPClient.send(_:)` validates the status code before running the response serializer. Override validation with ``StatusValidation`` when a request intentionally treats a non-2xx response as successful.
