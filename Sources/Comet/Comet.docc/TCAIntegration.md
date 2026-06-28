# TCA Integration

Use `CometTCA` when a Composable Architecture feature wants an injected ``HTTPClient`` and request effects.

## Inject A Client

```swift
import Comet
import CometTCA
import Dependencies

prepareDependencies {
  $0.httpClient = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://api.example.com")!),
    transport: URLSessionTransport()
  )
}
```

## Run A Request From A Reducer

```swift
import Comet
import CometTCA
import ComposableArchitecture

@Reducer
struct UserFeature {
  @ObservableState
  struct State: Equatable {
    var user: User?
  }

  enum Action {
    case task
    case userResponse(Result<User, NetworkError>)
  }

  @Dependency(\.httpClient) var httpClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        return .request(GetUser(userID: 42)) {
          .userResponse($0)
        }

      case .userResponse(.success(let user)):
        state.user = user
        return .none

      case .userResponse(.failure):
        return .none
      }
    }
  }
}
```

Use the `using:` overload when a feature needs a one-off client instead of the
dependency value:

```swift
return .request(GetUser(userID: 42), using: previewClient) {
  .userResponse($0)
}
```

## Track Request State

Use `CometRequestState` when a feature wants a small generic loading
state that keeps the previous value while a refresh is in flight.

```swift
state.user.start()

switch result {
case .success(let user):
  state.user.succeed(user)
case .failure(let error):
  state.user.fail(error)
}
```

Keep feature-specific error presentation in the feature. CometTCA stays intentionally small so the base package remains usable without TCA.
