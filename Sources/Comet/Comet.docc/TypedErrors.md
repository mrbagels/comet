# Typed API Errors

Decode structured HTTP error bodies without losing the raw ``NetworkError`` information.

## Define The Error Body

```swift
struct APIError: Decodable, Sendable {
  let code: String
  let message: String
}
```

## Declare Error Decoding On The Request

Use ``APIRequestWithErrorResponse`` when every caller of a request should share the same typed error model.

```swift
struct CreateUser: APIRequestWithErrorResponse {
  typealias Response = User
  typealias ErrorResponse = APIError

  let path: Path = "users"
  let method: HTTPMethod = .post
  let body: HTTPBody
  let responseSerializer: ResponseSerializer<User> = .json(User.self)
  let errorResponseSerializer: ErrorResponseSerializer<APIError> = .json(APIError.self)
}
```

## Send With Typed Errors

```swift
do {
  let user = try await client.sendWithTypedErrors(
    CreateUser(body: .json(draft))
  )
} catch let error as APIClientError<APIError> {
  if let apiError = error.decodedErrorBody {
    showMessage(apiError.message)
  } else {
    showMessage(error.networkError.debugSummary)
  }
}
```

Use `HTTPClient.send(_:errorResponseSerializer:)` when a call site wants typed errors without changing the request type.

If the error body cannot be decoded, Comet throws ``APIClientError/errorResponseDecodingFailed(networkError:decodingError:)`` so the raw HTTP status, headers, and body remain available.
