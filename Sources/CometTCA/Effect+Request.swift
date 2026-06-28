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
}
