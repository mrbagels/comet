import HTTPTypes

public protocol APIRequest: Sendable {
  associatedtype Response: Sendable

  var path: Path { get }
  var method: HTTPMethod { get }
  var headers: HTTPFields { get }
  var queryItems: [QueryItem] { get }
  var body: HTTPBody { get }
  var options: RequestOptions { get }
  var responseSerializer: ResponseSerializer<Response> { get }
}

public extension APIRequest {
  var headers: HTTPFields { .init() }
  var queryItems: [QueryItem] { [] }
  var body: HTTPBody { .none }
  var options: RequestOptions { .init() }
}
