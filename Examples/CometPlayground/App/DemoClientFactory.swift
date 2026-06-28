import Foundation
import HTTPTypes
import Comet
import CometTesting

enum DemoClientFactory {
  private static let liveWebSocketURL = URL(string: "wss://ws.postman-echo.com/raw")!

  static func makeClient(mode: DemoCatalog.ClientMode) -> HTTPClient {
    switch mode {
    case .mock:
      let routeState = DemoRouteState()
      return .live(
        configuration: ClientConfiguration(
          baseURL: URL(string: "https://comet.local")!,
          middleware: [
            RetryMiddleware(
              maxAttempts: 2,
              backoff: .constant(.milliseconds(1)),
              jitter: 0
            )
          ],
          sleep: { _ in },
          randomDouble: { _ in 1 }
        ),
        transport: MockTransport { request async throws(NetworkError) -> RawResponse in
          switch request.url.path {
          case "/todos/1":
            let data: Data
            do {
              data = try JSONEncoder().encode(
                DemoTodo(
                  userId: 7,
                  id: 1,
                  title: "Mock transport says hello",
                  completed: true
                )
              )
            } catch {
              throw NetworkError.encoding("Unable to encode mock todo response: \(error)")
            }

            return RawResponse(
              data: data,
              statusCode: 200,
              headers: {
                var headers = HTTPFields()
                headers[.contentType] = "application/json"
                return headers
              }()
            )

          case "/failures/timeout":
            throw NetworkError.timeout

          case "/failures/unauthorized":
            return try Self.jsonResponse(
              DemoAPIError(
                code: "unauthorized",
                message: "The mock API rejected the request with a typed error body."
              ),
              statusCode: 401
            )

          case "/failures/rate-limit":
            return await routeState.nextRateLimitResponse()

          case "/failures/server-error":
            return RawResponse(
              data: Data("Mock server returned a controlled 500.".utf8),
              statusCode: 500,
              headers: {
                var headers = HTTPFields()
                headers[.contentType] = "text/plain; charset=utf-8"
                return headers
              }()
            )

          case "/failures/malformed-json":
            return RawResponse(
              data: Data(#"{"id":"not-an-int","title":"Malformed"}"#.utf8),
              statusCode: 200,
              headers: {
                var headers = HTTPFields()
                headers[.contentType] = "application/json"
                return headers
              }()
            )

          case "/failures/cancelled":
            throw NetworkError.cancelled

          case "":
            return RawResponse(
              data: Data("Comet mock text response".utf8),
              statusCode: 200,
              headers: {
                var headers = HTTPFields()
                headers[.contentType] = "text/plain; charset=utf-8"
                return headers
              }()
            )

          case "/status/204":
            return RawResponse(data: Data(), statusCode: 204)

          default:
            throw NetworkError.invalidRequest("No mock handler registered for \(request.url.absoluteString).")
          }
        }
      )

    case .live:
      return .live(
        configuration: ClientConfiguration(
          baseURL: URL(string: "https://jsonplaceholder.typicode.com")!,
          middleware: [
            RetryMiddleware(
              maxAttempts: 2,
              backoff: .constant(.milliseconds(250)),
              jitter: 0
            )
          ]
        ),
        transport: URLSessionTransport()
      )
    }
  }

  static func makeWebSocketClient(mode: DemoCatalog.ClientMode) -> WebSocketClient {
    switch mode {
    case .mock:
      return .live(
        transport: MockWebSocketTransport(
          selectedSubprotocol: "comet.demo.v1",
          echoSentMessages: true
        )
      )

    case .live:
      return .live(
        transport: URLSessionWebSocketTransport(configuration: .ephemeral)
      )
    }
  }

  static func makeWebSocketRequest(mode: DemoCatalog.ClientMode) -> WebSocketRequest {
    switch mode {
    case .mock:
      return WebSocketRequest(
        url: URL(string: "wss://comet.local/socket")!,
        subprotocols: ["comet.demo.v1"],
        timeout: .seconds(10)
      )

    case .live:
      return WebSocketRequest(
        url: self.liveWebSocketURL,
        timeout: .seconds(10)
      )
    }
  }

  private static func jsonResponse<Value: Encodable & Sendable>(
    _ value: Value,
    statusCode: Int
  ) throws(NetworkError) -> RawResponse {
    do {
      let data = try JSONEncoder().encode(value)
      return RawResponse(
        data: data,
        statusCode: statusCode,
        headers: {
          var headers = HTTPFields()
          headers[.contentType] = "application/json"
          return headers
        }()
      )
    } catch {
      throw NetworkError.encoding("Unable to encode mock JSON response: \(error)")
    }
  }
}

private actor DemoRouteState {
  private var rateLimitAttempt = 0

  func nextRateLimitResponse() -> RawResponse {
    self.rateLimitAttempt += 1

    if self.rateLimitAttempt.isMultiple(of: 2) {
      return RawResponse(
        data: Data("Retried after a mock 429 and recovered.".utf8),
        statusCode: 200,
        headers: {
          var headers = HTTPFields()
          headers[.contentType] = "text/plain; charset=utf-8"
          return headers
        }()
      )
    } else {
      return RawResponse(
        data: Data("Slow down.".utf8),
        statusCode: 429,
        headers: {
          var headers = HTTPFields()
          headers[.contentType] = "text/plain; charset=utf-8"
          return headers
        }()
      )
    }
  }
}
