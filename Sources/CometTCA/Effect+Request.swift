import ComposableArchitecture
import Comet

public extension Effect where Action: Sendable {
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
