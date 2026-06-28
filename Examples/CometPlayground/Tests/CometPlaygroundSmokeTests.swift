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
    XCTAssertGreaterThanOrEqual(model.activityLog.count, DemoCatalog.Demo.allCases.count)
  }

  func testTypedRequestsDoNotInjectAPIVersion() {
    XCTAssertNil(TodoRequest().options.apiVersion)
    XCTAssertNil(RawTodoRequest().options.apiVersion)
    XCTAssertNil(TimeoutDemoRequest(mode: .mock).options.apiVersion)
    XCTAssertNil(UnauthorizedDemoRequest(mode: .mock).options.apiVersion)
  }
}
