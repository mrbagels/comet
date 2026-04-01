import Foundation
import Testing
import Comet
import CometTesting

@Test func mockTransportReturnsRegisteredResponse() async throws {
  let transport = MockTransport.responses([
    "/ping": RawResponse(data: Data("pong".utf8), statusCode: 200)
  ])

  let response = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/ping")!,
      method: .get,
      timeout: .seconds(1)
    )
  )

  #expect(String(decoding: response.data, as: UTF8.self) == "pong")
}

@Test func recordingTransportCapturesRequests() async throws {
  let base = MockTransport { _ in
    RawResponse(data: Data(), statusCode: 200)
  }
  let transport = RecordingTransport(base: base)

  _ = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/test")!,
      method: .get,
      timeout: .seconds(1)
    )
  )

  let recorded = await transport.recorded()
  #expect(recorded.count == 1)
  #expect(recorded.first?.url.absoluteString == "https://example.com/test")
}

@Test func mockTransportRoutesCanMatchMethodAndQuery() async throws {
  let transport = MockTransport.routes([
    .init(method: .get, path: "/items", query: "page=2"):
      RawResponse(data: Data("two".utf8), statusCode: 200)
  ])

  let response = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/items?page=2")!,
      method: .get,
      timeout: .seconds(1)
    )
  )

  #expect(String(decoding: response.data, as: UTF8.self) == "two")
}
