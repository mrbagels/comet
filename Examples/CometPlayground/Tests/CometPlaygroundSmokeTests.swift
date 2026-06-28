import XCTest
@testable import CometPlaygroundApp

final class CometPlaygroundSmokeTests: XCTestCase {
  @MainActor
  func testCatalogStartsInMockMode() {
    let model = DemoCatalog()

    XCTAssertEqual(model.mode, .mock)
    XCTAssertEqual(model.completedChecks, 0)
  }

  @MainActor
  func testMockProofRunsEveryDemo() async {
    let model = DemoCatalog()

    await model.runMockProof()

    for _ in 0..<20 where model.activityLog.count < DemoCatalog.Demo.allCases.count {
      await Task.yield()
    }

    XCTAssertEqual(model.completedChecks, DemoCatalog.Demo.allCases.count)
    XCTAssertTrue(model.state(for: .json).output.contains("Mock transport says hello"))
    XCTAssertTrue(model.state(for: .text).output.contains("Comet mock text response"))
    XCTAssertTrue(model.state(for: .empty).output.contains("EmptyResponse"))
    XCTAssertTrue(model.state(for: .raw).output.contains("status: 200"))
    XCTAssertTrue(model.state(for: .timeout).output.contains("timeout"))
    XCTAssertTrue(model.state(for: .unauthorized).output.contains("unauthorized"))
    XCTAssertTrue(model.state(for: .rateLimited).output.contains("recovered after retry"))
    XCTAssertTrue(model.state(for: .serverError).output.contains("500"))
    XCTAssertTrue(model.state(for: .malformedJSON).output.contains("Decoding error"))
    XCTAssertTrue(model.state(for: .cancelled).output.contains("cancelled"))
    XCTAssertTrue(model.state(for: .webSocket).output.contains("\"transport\" : \"MockWebSocketTransport\""))
    XCTAssertTrue(model.state(for: .webSocket).output.contains("\"negotiatedSubprotocol\" : \"comet.demo.v1\""))
    XCTAssertTrue(model.state(for: .webSocketClose).output.contains("WebSocket closed"))
    XCTAssertEqual(model.state(for: .raw).response?.fields.first { $0.label == "Status" }?.value, "200")
    XCTAssertTrue(model.state(for: .json).response?.body.contains("Mock transport says hello") == true)
    XCTAssertTrue(model.state(for: .serverError).response?.rawValue.contains("Status: 500") == true)
    XCTAssertEqual(model.state(for: .webSocket).socket?.frames.count, 3)
    XCTAssertTrue(model.state(for: .webSocket).socket?.rawValue.contains("MockWebSocketTransport") == true)
    XCTAssertEqual(
      model.state(for: .webSocketClose).socket?.fields.first { $0.label == "Close code" }?.value,
      "1001"
    )
    XCTAssertGreaterThanOrEqual(model.activityLog.count, DemoCatalog.Demo.allCases.count)
    XCTAssertTrue(model.activityLog.contains { $0.kind == .failed })
    XCTAssertTrue(model.activityLog.contains { $0.kind == .retried })
    XCTAssertTrue(model.activityLog.contains { $0.kind == .socket })
  }

  func testTypedRequestsDoNotInjectAPIVersion() {
    XCTAssertNil(TodoRequest().options.apiVersion)
    XCTAssertNil(RawTodoRequest().options.apiVersion)
    XCTAssertNil(TimeoutDemoRequest(mode: .mock).options.apiVersion)
    XCTAssertNil(UnauthorizedDemoRequest(mode: .mock).options.apiVersion)
  }

  @MainActor
  func testRequestInspectorUsesPreparedRequests() {
    let model = DemoCatalog()

    let unauthorized = model.requestInspection(for: .unauthorized)
    XCTAssertEqual(unauthorized.method, "GET")
    XCTAssertTrue(unauthorized.url.contains("https://comet.local/failures/unauthorized"))
    XCTAssertTrue(unauthorized.curlCommand?.contains("curl") == true)
    XCTAssertTrue(unauthorized.fields.contains { $0.label == "Typed error" })

    let socketClose = model.requestInspection(for: .webSocketClose)
    XCTAssertEqual(socketClose.transport, "MockWebSocketTransport")
    XCTAssertEqual(socketClose.method, "GET")
    XCTAssertFalse(socketClose.hasCurlCommand)
  }
}
