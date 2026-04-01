import Dependencies
import Comet

private enum CometHTTPClientKey: DependencyKey {
  static let liveValue = HTTPClient.failing(
    with: .invalidRequest("HTTPClient dependency has not been configured.")
  )
  static let testValue = HTTPClient.failing(
    with: .invalidRequest("HTTPClient dependency has not been configured for tests.")
  )
}

public extension DependencyValues {
  var httpClient: HTTPClient {
    get { self[CometHTTPClientKey.self] }
    set { self[CometHTTPClientKey.self] = newValue }
  }
}
