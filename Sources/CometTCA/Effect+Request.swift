import ComposableArchitecture
import Comet

public extension Effect where Action: Sendable {
  /// Builds an effect that executes a Comet request with the injected ``HTTPClient`` dependency.
  static func request<R: APIRequest>(
    _ request: R,
    map: @escaping @Sendable (Result<R.Response, NetworkError>) -> Action
  ) -> Self {
    @Dependency(\.httpClient) var client
    return .request(request, using: client, map: map)
  }

  /// Builds an effect that executes a Comet request and maps the typed result into an action.
  static func request<R: APIRequest>(
    _ request: R,
    using client: HTTPClient,
    map: @escaping @Sendable (Result<R.Response, NetworkError>) -> Action
  ) -> Self {
    .run { send in
      do {
        await send(map(.success(try await client.send(request))))
      } catch let error as NetworkError {
        await send(map(.failure(error)))
      } catch {
        await send(map(.failure(.from(error))))
      }
    }
  }

  /// Builds an effect that emits request lifecycle actions around a Comet request.
  static func trackedRequest<R: APIRequest>(
    _ request: R,
    action: @escaping @Sendable (CometRequestAction<R.Response>) -> Action
  ) -> Self {
    @Dependency(\.httpClient) var client
    return .trackedRequest(request, using: client, action: action)
  }

  /// Builds a cancellable effect that emits request lifecycle actions around a Comet request.
  static func trackedRequest<R: APIRequest, CancellationID: Hashable & Sendable>(
    _ request: R,
    cancellationID: CancellationID,
    cancelInFlight: Bool = true,
    action: @escaping @Sendable (CometRequestAction<R.Response>) -> Action
  ) -> Self {
    @Dependency(\.httpClient) var client
    return .trackedRequest(
      request,
      using: client,
      cancellationID: cancellationID,
      cancelInFlight: cancelInFlight,
      action: action
    )
  }

  /// Builds an effect that emits request lifecycle actions around a Comet request using an explicit client.
  static func trackedRequest<R: APIRequest>(
    _ request: R,
    using client: HTTPClient,
    action: @escaping @Sendable (CometRequestAction<R.Response>) -> Action
  ) -> Self {
    .concatenate(
      .send(action(.started)),
      .request(request, using: client) { result in
        action(.response(result))
      }
    )
  }

  /// Builds a cancellable effect that emits request lifecycle actions using an explicit client.
  static func trackedRequest<R: APIRequest, CancellationID: Hashable & Sendable>(
    _ request: R,
    using client: HTTPClient,
    cancellationID: CancellationID,
    cancelInFlight: Bool = true,
    action: @escaping @Sendable (CometRequestAction<R.Response>) -> Action
  ) -> Self {
    .trackedRequest(request, using: client, action: action)
      .cancellable(id: cancellationID, cancelInFlight: cancelInFlight)
  }
}
