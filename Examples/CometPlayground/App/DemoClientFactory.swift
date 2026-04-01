import Foundation
import HTTPTypes
import Comet
import CometTesting

enum DemoClientFactory {
  private static let liveWebSocketURL = URL(string: "wss://ws.postman-echo.com/raw")!

  static func makeClient(mode: DemoCatalog.ClientMode) -> HTTPClient {
    switch mode {
    case .mock:
      return .live(
        configuration: .default(baseURL: URL(string: "https://comet.local")!),
        transport: MockTransport { request throws(NetworkError) -> RawResponse in
          switch request.url.absoluteString {
          case "https://comet.local/todos/1":
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

          case "https://example.com":
            return RawResponse(
              data: Data("Comet mock text response".utf8),
              statusCode: 200,
              headers: {
                var headers = HTTPFields()
                headers[.contentType] = "text/plain; charset=utf-8"
                return headers
              }()
            )

          case "https://httpbin.org/status/204":
            return RawResponse(data: Data(), statusCode: 204)

          default:
            throw NetworkError.invalidRequest("No mock handler registered for \(request.url.absoluteString).")
          }
        }
      )

    case .live:
      return .live(
        configuration: .default(baseURL: URL(string: "https://jsonplaceholder.typicode.com")!),
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
}
