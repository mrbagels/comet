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
