import HTTPTypes

/// Describes a typed HTTP request that Comet can build, execute, and decode.
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

/// Provides sensible defaults for optional request customization points.
public extension APIRequest {
  var headers: HTTPFields { .init() }
  var queryItems: [QueryItem] { [] }
  var body: HTTPBody { .none }
  var options: RequestOptions { .init() }
}

/// Describes a typed request that can decode structured unsuccessful HTTP responses.
public protocol APIRequestWithErrorResponse: APIRequest {
  associatedtype ErrorResponse: Sendable

  var errorResponseSerializer: ErrorResponseSerializer<ErrorResponse> { get }
}
