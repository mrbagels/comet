import Foundation
import Testing
import HTTPTypes
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
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    return RawResponse(data: Data(#"{"ok":true}"#.utf8), statusCode: 200, headers: headers)
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

  let exchanges = await transport.recordedExchanges()
  #expect(exchanges.count == 1)
  #expect(exchanges.first?.durationMilliseconds ?? -1 >= 0)

  guard case .success(let recordedResponse) = exchanges.first?.outcome else {
    Issue.record("Expected the recorded exchange to store a response.")
    return
  }

  #expect(recordedResponse.statusCode == 200)
  #expect(recordedResponse.bodyData == Data(#"{"ok":true}"#.utf8))
}

@Test func recordingTransportCapturesFailuresAndExportsCassette() async throws {
  let transport = RecordingTransport(base: MockTransport { (_: PreparedRequest) throws(NetworkError) -> RawResponse in
    throw NetworkError.http(
      statusCode: 503,
      body: Data(#"{"message":"offline"}"#.utf8),
      headers: {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return headers
      }()
    )
  })

  await #expect(throws: NetworkError.self) {
    _ = try await transport.send(
      PreparedRequest(
        url: URL(string: "https://example.com/failing")!,
        method: .get,
        timeout: .seconds(1)
      )
    )
  }

  let cassette = await transport.cassette()
  #expect(cassette.exchanges.count == 1)

  guard case .failure(let recordedError) = cassette.exchanges.first?.outcome else {
    Issue.record("Expected the cassette to record the failure.")
    return
  }

  #expect(recordedError.kind == .http)
  #expect(recordedError.statusCode == 503)
  #expect(recordedError.bodyData == Data(#"{"message":"offline"}"#.utf8))
}

@Test func cassetteRoundTripsThroughJSON() throws {
  let recordedAt = Date(timeIntervalSince1970: 1_717_171_717)
  let cassette = HTTPCassette(
    recordedAt: recordedAt,
    exchanges: [
      RecordedExchange(
        recordedAt: recordedAt,
        request: RecordedRequest(
          method: "GET",
          url: "https://example.com/todos/1",
          headers: [RecordedHeader(name: "accept", value: "application/json")],
          timeoutMilliseconds: 1_000
        ),
        duration: .milliseconds(42),
        outcome: .success(
          RecordedResponse(
            statusCode: 200,
            headers: [RecordedHeader(name: "content-type", value: "application/json")],
            bodyBase64: Data(#"{"id":1}"#.utf8).base64EncodedString()
          )
        )
      )
    ]
  )

  let encoded = try cassette.encoded()
  let decoded = try HTTPCassette.jsonDecoder().decode(HTTPCassette.self, from: encoded)

  #expect(decoded == cassette)
}

@Test func replayTransportReplaysRecordedResponses() async throws {
  let cassette = HTTPCassette(
    exchanges: [
      RecordedExchange(
        request: RecordedRequest(
          method: "GET",
          url: "https://example.com/items?page=2",
          timeoutMilliseconds: 1_000
        ),
        duration: .milliseconds(12),
        outcome: .success(
          RecordedResponse(
            statusCode: 200,
            headers: [RecordedHeader(name: "content-type", value: "text/plain")],
            bodyBase64: Data("two".utf8).base64EncodedString()
          )
        )
      )
    ]
  )

  let transport = ReplayTransport(cassette: cassette)
  let response = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/items?page=2")!,
      method: .get,
      timeout: .seconds(1)
    )
  )

  #expect(String(decoding: response.data, as: UTF8.self) == "two")
  #expect(response.statusCode == 200)
  #expect(await transport.remainingCount() == 0)
}

@Test func replayTransportReplaysRecordedFailures() async {
  let cassette = HTTPCassette(
    exchanges: [
      RecordedExchange(
        request: RecordedRequest(
          method: "POST",
          url: "https://example.com/todos",
          bodyBase64: Data("{}".utf8).base64EncodedString(),
          timeoutMilliseconds: 1_000
        ),
        duration: .milliseconds(19),
        outcome: .failure(
          RecordedNetworkError(
            kind: .http,
            statusCode: 422,
            headers: [RecordedHeader(name: "content-type", value: "application/json")],
            bodyBase64: Data(#"{"error":"bad input"}"#.utf8).base64EncodedString()
          )
        )
      )
    ]
  )

  let transport = ReplayTransport(cassette: cassette)

  await #expect(throws: NetworkError.self) {
    _ = try await transport.send(
      PreparedRequest(
        url: URL(string: "https://example.com/todos")!,
        method: .post,
        body: Data("{}".utf8),
        timeout: .seconds(1)
      )
    )
  }
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
