import Foundation
import Comet

struct TodoRequest: APIRequest {
  typealias Response = DemoTodo

  let path: Path = "todos" / 1
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<DemoTodo> = .json(DemoTodo.self)
  let options = RequestOptions(apiVersion: nil)
}

struct TextDemoRequest: APIRequest {
  typealias Response = String

  let path: Path = "plain-text"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()
  let options = RequestOptions(
    apiVersion: nil,
    absoluteURL: URL(string: "https://example.com")!
  )
}

struct EmptyDemoRequest: APIRequest {
  typealias Response = EmptyResponse

  let path: Path = "empty"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<EmptyResponse> = .empty
  let options = RequestOptions(
    apiVersion: nil,
    absoluteURL: URL(string: "https://httpbin.org/status/204")!
  )
}

struct RawTodoRequest: APIRequest {
  typealias Response = DemoTodo

  let path: Path = "todos" / 1
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<DemoTodo> = .json(DemoTodo.self)
  let options = RequestOptions(apiVersion: nil)
}

struct TimeoutDemoRequest: APIRequest {
  typealias Response = String

  let mode: DemoCatalog.ClientMode
  let path: Path = "failures" / "timeout"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()

  var options: RequestOptions {
    RequestOptions(
      apiVersion: nil,
      absoluteURL: mode == .live ? URL(string: "https://httpbin.org/delay/10")! : nil,
      timeout: .seconds(1),
      metadata: RequestMetadata(name: "TimeoutDemo", tags: ["failures"])
    )
  }
}

struct UnauthorizedDemoRequest: APIRequestWithErrorResponse {
  typealias Response = String
  typealias ErrorResponse = DemoAPIError

  let mode: DemoCatalog.ClientMode
  let path: Path = "failures" / "unauthorized"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()
  let errorResponseSerializer: ErrorResponseSerializer<DemoAPIError> = .json(DemoAPIError.self)

  var options: RequestOptions {
    RequestOptions(
      apiVersion: nil,
      absoluteURL: mode == .live ? URL(string: "https://httpbin.org/status/401")! : nil,
      metadata: RequestMetadata(name: "UnauthorizedDemo", tags: ["failures", "typed-errors"])
    )
  }
}

struct RateLimitDemoRequest: APIRequest {
  typealias Response = String

  let mode: DemoCatalog.ClientMode
  let path: Path = "failures" / "rate-limit"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()

  var options: RequestOptions {
    RequestOptions(
      apiVersion: nil,
      absoluteURL: mode == .live ? URL(string: "https://httpbin.org/status/429")! : nil,
      metadata: RequestMetadata(name: "RateLimitDemo", tags: ["failures", "retries"])
    )
  }
}

struct ServerErrorDemoRequest: APIRequest {
  typealias Response = String

  let mode: DemoCatalog.ClientMode
  let path: Path = "failures" / "server-error"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()

  var options: RequestOptions {
    RequestOptions(
      apiVersion: nil,
      absoluteURL: mode == .live ? URL(string: "https://httpbin.org/status/500")! : nil,
      metadata: RequestMetadata(name: "ServerErrorDemo", tags: ["failures"])
    )
  }
}

struct MalformedJSONDemoRequest: APIRequest {
  typealias Response = DemoTodo

  let mode: DemoCatalog.ClientMode
  let path: Path = "failures" / "malformed-json"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<DemoTodo> = .json(DemoTodo.self)

  var options: RequestOptions {
    RequestOptions(
      apiVersion: nil,
      absoluteURL: mode == .live ? URL(string: "https://example.com")! : nil,
      metadata: RequestMetadata(name: "MalformedJSONDemo", tags: ["failures", "decoding"])
    )
  }
}

struct CancelledDemoRequest: APIRequest {
  typealias Response = String

  let path: Path = "failures" / "cancelled"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()
  let options = RequestOptions(
    apiVersion: nil,
    metadata: RequestMetadata(name: "CancelledDemo", tags: ["failures"])
  )
}
