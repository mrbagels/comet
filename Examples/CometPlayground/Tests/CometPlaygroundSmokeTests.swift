import Dependencies
import XCTest
@testable import CometPlaygroundApp

final class CometPlaygroundSmokeTests: XCTestCase {
  @MainActor
  func testCatalogStartsInMockMode() {
    let model = makeCatalog()

    XCTAssertEqual(model.mode, .mock)
    XCTAssertEqual(model.completedChecks, 0)
  }

  @MainActor
  func testMockProofRunsEveryDemo() async {
    let model = makeCatalog()

    await model.runMockProof()

    for _ in 0..<20 where model.activityLog.count < DemoCatalog.Demo.allCases.count {
      await Task.yield()
    }
    for _ in 0..<50 {
      if model.traceTimeline(for: .rateLimited)?.events.contains(where: { $0.kind == .retried }) == true {
        break
      }
      await Task.yield()
    }

    XCTAssertEqual(model.completedChecks, DemoCatalog.Demo.allCases.count)
    XCTAssertTrue(model.state(for: .json).output.contains("Mock transport says hello"))
    XCTAssertTrue(model.state(for: .text).output.contains("Comet mock text response"))
    XCTAssertTrue(model.state(for: .empty).output.contains("EmptyResponse"))
    XCTAssertTrue(model.state(for: .raw).output.contains("status: 200"))
    XCTAssertTrue(model.state(for: .cacheLab).output.contains("fresh hit: cache lab payload v1"))
    XCTAssertTrue(model.state(for: .cacheLab).output.contains("stale events: stale(stale) -> revalidate -> update(notModified)"))
    XCTAssertTrue(model.state(for: .cacheLab).output.contains("fallback events: stale(stale) -> revalidate -> hit(staleIfError)"))
    XCTAssertTrue(model.state(for: .cacheLab).output.contains("cache entries after clear: 0"))
    XCTAssertTrue(model.state(for: .contractServer).output.contains("report passed: true"))
    XCTAssertTrue(model.state(for: .contractServer).output.contains("matches: contract-profile-happy-path"))
    XCTAssertTrue(model.state(for: .contractServer).output.contains("violations: 0"))
    XCTAssertTrue(model.state(for: .timeout).output.contains("timeout"))
    XCTAssertTrue(model.state(for: .unauthorized).output.contains("unauthorized"))
    XCTAssertTrue(model.state(for: .rateLimited).output.contains("recovered after retry"))
    XCTAssertTrue(model.state(for: .raw).output.contains("traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736"))
    XCTAssertTrue(model.state(for: .serverError).output.contains("500"))
    XCTAssertTrue(model.state(for: .malformedJSON).output.contains("Decoding error"))
    XCTAssertTrue(model.state(for: .cancelled).output.contains("cancelled"))
    XCTAssertTrue(model.state(for: .webSocket).output.contains("\"transport\" : \"MockWebSocketTransport\""))
    XCTAssertTrue(model.state(for: .webSocket).output.contains("\"negotiatedSubprotocol\" : \"comet.demo.v1\""))
    XCTAssertTrue(model.state(for: .webSocketClose).output.contains("WebSocket closed"))
    XCTAssertEqual(model.state(for: .raw).response?.fields.first { $0.label == "Status" }?.value, "200")
    XCTAssertTrue(
      model.state(for: .raw).response?.fields
        .first { $0.label == "Traceparent" }?
        .value
        .hasPrefix("00-4bf92f3577b34da6a3ce929d0e0e4736") == true
    )
    XCTAssertTrue(model.state(for: .json).response?.body.contains("Mock transport says hello") == true)
    XCTAssertTrue(model.state(for: .serverError).response?.rawValue.contains("Status: 500") == true)
    XCTAssertEqual(
      model.state(for: .cacheLab).response?.fields.first { $0.label == "After clear" }?.value,
      "0 entries"
    )
    XCTAssertEqual(
      model.state(for: .contractServer).response?.fields.first { $0.label == "Report" }?.value,
      "Passed"
    )
    XCTAssertEqual(model.state(for: .webSocket).socket?.frames.count, 3)
    XCTAssertTrue(model.state(for: .webSocket).socket?.rawValue.contains("MockWebSocketTransport") == true)
    XCTAssertEqual(
      model.state(for: .webSocketClose).socket?.fields.first { $0.label == "Close code" }?.value,
      "1001"
    )
    XCTAssertTrue(model.state(for: .json).cassette?.json.contains("\"exchanges\"") == true)
    XCTAssertEqual(
      model.state(for: .json).cassette?.fields.first { $0.label == "Replay" }?.value,
      "Verified"
    )
    XCTAssertTrue(model.state(for: .json).cassette?.replayOutput?.contains("success replay") == true)
    XCTAssertEqual(
      model.state(for: .rateLimited).cassette?.fields.first { $0.label == "Exchanges" }?.value,
      "2"
    )
    XCTAssertTrue(model.state(for: .rateLimited).cassette?.replayOutput?.contains("consumed: 2/2") == true)
    XCTAssertTrue(model.state(for: .timeout).cassette?.json.contains("\"timeout\"") == true)
    XCTAssertTrue(model.state(for: .timeout).cassette?.replayOutput?.contains("expected failure replay") == true)
    let rateLimitTrace = model.traceTimeline(for: .rateLimited)
    XCTAssertEqual(rateLimitTrace?.fields.first { $0.label == "Correlation" }?.value.count, 8)
    XCTAssertEqual(rateLimitTrace?.events.map(\.kind), [.started, .retried, .completed])
    XCTAssertTrue(rateLimitTrace?.rawValue.contains("RateLimitDemo") == true)
    let socketTrace = model.traceTimeline(for: .webSocket)
    XCTAssertEqual(socketTrace?.events.count, 2)
    XCTAssertTrue(socketTrace?.events.allSatisfy { $0.kind == .socket } == true)
    XCTAssertGreaterThanOrEqual(model.activityLog.count, DemoCatalog.Demo.allCases.count)
    XCTAssertTrue(model.activityLog.contains { $0.kind == .failed })
    XCTAssertTrue(model.activityLog.contains { $0.kind == .retried })
    XCTAssertTrue(model.activityLog.contains { $0.kind == .socket })
  }

  func testTypedRequestsDoNotInjectAPIVersion() {
    XCTAssertNil(TodoRequest().options.apiVersion)
    XCTAssertNil(RawTodoRequest().options.apiVersion)
    XCTAssertNil(CacheLabRequest().options.apiVersion)
    XCTAssertNil(ContractServerDemoRequest().options.apiVersion)
    XCTAssertNil(TimeoutDemoRequest(mode: .mock).options.apiVersion)
    XCTAssertNil(UnauthorizedDemoRequest(mode: .mock).options.apiVersion)
  }

  func testTCADemoStartsIdle() {
    let state = TCADemoFeature.State()

    XCTAssertEqual(state.status, .idle)
    XCTAssertEqual(state.output, "Run the request from a TCA reducer.")
    XCTAssertTrue(state.fields.isEmpty)
    XCTAssertFalse(state.request.isLoading)
  }

  @MainActor
  func testRequestInspectorUsesPreparedRequests() {
    let model = makeCatalog()

    let unauthorized = model.requestInspection(for: .unauthorized)
    XCTAssertEqual(unauthorized.method, "GET")
    XCTAssertTrue(unauthorized.url.contains("https://comet.local/failures/unauthorized"))
    XCTAssertTrue(unauthorized.curlCommand?.contains("curl") == true)
    XCTAssertTrue(unauthorized.fields.contains { $0.label == "Typed error" })

    let raw = model.requestInspection(for: .raw)
    XCTAssertEqual(
      raw.fields.first { $0.label == "Trace ID" }?.value,
      "4bf92f3577b34da6a3ce929d0e0e4736"
    )

    let cacheLab = model.requestInspection(for: .cacheLab)
    XCTAssertEqual(cacheLab.transport, "MockTransport + FileHTTPCacheStore")
    XCTAssertTrue(cacheLab.fields.contains { $0.label == "Cache policy" })

    let contractServer = model.requestInspection(for: .contractServer)
    XCTAssertEqual(contractServer.transport, "MockServer + ContractTransport")
    XCTAssertTrue(contractServer.fields.contains { $0.label == "Expectation" })

    let socketClose = model.requestInspection(for: .webSocketClose)
    XCTAssertEqual(socketClose.transport, "MockWebSocketTransport")
    XCTAssertEqual(socketClose.method, "GET")
    XCTAssertFalse(socketClose.hasCurlCommand)
  }

  @MainActor
  private func makeCatalog() -> DemoCatalog {
    withDependencies {
      try! $0.bootstrapDatabase()
    } operation: {
      DemoCatalog()
    }
  }
}
