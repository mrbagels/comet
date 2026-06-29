import Foundation
import Testing
import HTTPTypes
import Comet
import CometTesting

private struct LocalMockServerGetRequest: APIRequest {
  let path: Path = "local"
  let method: HTTPMethod = .get
  var queryItems: [QueryItem] = [
    .init("expand", "details")
  ]
  let responseSerializer: ResponseSerializer<String> = .string()
}

private struct LocalMockServerPostRequest: APIRequest {
  let path: Path = "local"
  let method: HTTPMethod = .post
  let body: HTTPBody = .text("payload", contentType: "text/plain")
  let responseSerializer: ResponseSerializer<String> = .string()
}

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

@Test func recordingTransportRedactsSensitiveHeadersByDefault() async throws {
  let transport = RecordingTransport(
    base: MockTransport { _ in
      var headers = HTTPFields()
      headers[HTTPField.Name("Set-Cookie")!] = "session=secret"
      return RawResponse(data: Data("ok".utf8), statusCode: 200, headers: headers)
    }
  )

  var requestHeaders = HTTPFields()
  requestHeaders[.authorization] = "Bearer secret"
  requestHeaders[.cookie] = "session=secret"

  _ = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/private")!,
      method: .get,
      headers: requestHeaders,
      timeout: .seconds(1)
    )
  )

  let exchange = await transport.recordedExchanges().first

  #expect(exchange?.request.headers.contains(RecordedHeader(name: "Authorization", value: "<redacted>")) == true)
  #expect(exchange?.request.headers.contains(RecordedHeader(name: "Cookie", value: "<redacted>")) == true)

  guard case .success(let response) = exchange?.outcome else {
    Issue.record("Expected the exchange to record a response.")
    return
  }

  #expect(response.headers.contains(RecordedHeader(name: "Set-Cookie", value: "<redacted>")))
}

@Test func recordingTransportCanRedactBodiesBeforeWritingCassettes() async throws {
  let redaction = RecordingRedaction(
    redactRequestBody: { _ in true },
    redactResponseBody: { _ in true }
  )
  let transport = RecordingTransport(
    base: MockTransport { _ in
      RawResponse(data: Data("private response".utf8), statusCode: 200)
    },
    redaction: redaction
  )

  _ = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/private")!,
      method: .post,
      body: Data("private request".utf8),
      timeout: .seconds(1)
    )
  )

  let cassette = await transport.cassette()
  let exchange = try #require(cassette.exchanges.first)

  #expect(exchange.request.bodyWasRedacted)
  #expect(exchange.request.bodyData == Data("<redacted>".utf8))

  guard case .success(let response) = exchange.outcome else {
    Issue.record("Expected the exchange to record a response.")
    return
  }

  #expect(response.bodyWasRedacted)
  #expect(response.bodyData == Data("<redacted>".utf8))

  let replay = ReplayTransport(cassette: cassette)
  let replayed = try await replay.send(
    PreparedRequest(
      url: URL(string: "https://example.com/private")!,
      method: .post,
      body: Data("different request body".utf8),
      timeout: .seconds(1)
    )
  )

  #expect(replayed.data == Data("<redacted>".utf8))
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

@Test func replayTransportRejectsInvalidResponseBodyBase64() async {
  let cassette = HTTPCassette(
    exchanges: [
      RecordedExchange(
        request: RecordedRequest(
          method: "GET",
          url: "https://example.com/items",
          timeoutMilliseconds: 1_000
        ),
        duration: .milliseconds(1),
        outcome: .success(
          RecordedResponse(
            statusCode: 200,
            bodyBase64: "not base64"
          )
        )
      )
    ]
  )
  let transport = ReplayTransport(cassette: cassette)

  await #expect(throws: NetworkError.self) {
    _ = try await transport.send(
      PreparedRequest(
        url: URL(string: "https://example.com/items")!,
        method: .get,
        timeout: .seconds(1)
      )
    )
  }
}

@Test func recordedRequestsWithInvalidBodyBase64DoNotMatchOrRebuild() throws {
  let recorded = RecordedRequest(
    method: "POST",
    url: "https://example.com/items",
    bodyBase64: "not base64",
    timeoutMilliseconds: 1_000
  )
  let request = PreparedRequest(
    url: URL(string: "https://example.com/items")!,
    method: .post,
    timeout: .seconds(1)
  )

  #expect(!recorded.matches(request))
  #expect(throws: NetworkError.self) {
    _ = try recorded.makePreparedRequest()
  }
}

@Test func recordedNetworkErrorsRejectInvalidBodyBase64() async {
  let cassette = HTTPCassette(
    exchanges: [
      RecordedExchange(
        request: RecordedRequest(
          method: "GET",
          url: "https://example.com/failing",
          timeoutMilliseconds: 1_000
        ),
        duration: .milliseconds(1),
        outcome: .failure(
          RecordedNetworkError(
            kind: .http,
            statusCode: 500,
            bodyBase64: "not base64"
          )
        )
      )
    ]
  )
  let transport = ReplayTransport(cassette: cassette)

  await #expect(throws: NetworkError.self) {
    _ = try await transport.send(
      PreparedRequest(
        url: URL(string: "https://example.com/failing")!,
        method: .get,
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

@Test func contractTransportMatchesExactExpectation() async throws {
  var headers = HTTPFields()
  headers[.accept] = "application/json"

  let transport = ContractTransport(
    expectations: [
      ContractExpectation(
        id: "get-item",
        method: .get,
        path: "/items/1",
        query: [ContractQueryExpectation(name: "expand", value: .exact("owner"))],
        headers: [ContractHeaderExpectation(name: "accept", value: .exact("application/json"))],
        body: .absent,
        metadata: ContractMetadataExpectation(
          name: .exact("GetItem"),
          operationID: .exact("getItem"),
          tags: ["items"]
        ),
        outcome: .response(RawResponse(data: Data(#"{"id":1}"#.utf8), statusCode: 200))
      )
    ]
  )

  let response = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/items/1?expand=owner")!,
      method: .get,
      headers: headers,
      timeout: .seconds(1),
      metadata: RequestMetadata(name: "GetItem", tags: ["items"], operationID: "getItem")
    )
  )

  #expect(response.statusCode == 200)
  #expect(String(decoding: response.data, as: UTF8.self) == #"{"id":1}"#)

  try await transport.verifyComplete()
  let report = await transport.report(generatedAt: Date(timeIntervalSince1970: 0))
  #expect(report.passed)
  #expect(report.matches.map(\.expectationID) == ["get-item"])
}

@Test func contractTransportSupportsFlexibleHeaderMatching() async throws {
  let transport = ContractTransport(
    expectations: [
      ContractExpectation(
        id: "auth-header",
        method: .get,
        path: "/private",
        headers: [ContractHeaderExpectation(name: "authorization", value: .any)],
        outcome: .response(RawResponse(data: Data("ok".utf8), statusCode: 200))
      )
    ]
  )

  var headers = HTTPFields()
  headers[.authorization] = "Bearer token"

  let response = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/private")!,
      method: .get,
      headers: headers,
      timeout: .seconds(1)
    )
  )

  #expect(String(decoding: response.data, as: UTF8.self) == "ok")
  try await transport.verifyComplete()
}

@Test func contractTransportReportsBodyMismatches() async throws {
  let transport = ContractTransport(
    expectations: [
      ContractExpectation(
        id: "create-item",
        method: .post,
        path: "/items",
        body: .exact(Data(#"{"name":"expected"}"#.utf8)),
        outcome: .response(RawResponse(data: Data("created".utf8), statusCode: 201))
      )
    ]
  )

  await #expect(throws: NetworkError.self) {
    _ = try await transport.send(
      PreparedRequest(
        url: URL(string: "https://example.com/items")!,
        method: .post,
        body: Data(#"{"name":"actual"}"#.utf8),
        timeout: .seconds(1)
      )
    )
  }

  let report = await transport.report(generatedAt: Date(timeIntervalSince1970: 0))
  let violation = try #require(report.violations.first)

  #expect(!report.passed)
  #expect(violation.kind == .mismatch)
  #expect(violation.expectationID == "create-item")
  #expect(violation.differences.map(\.field) == ["body"])
}

@Test func contractTransportReportsUnexpectedRequestsAndUnusedExpectations() async throws {
  let transport = ContractTransport(
    expectations: [
      ContractExpectation(
        id: "expected",
        method: .get,
        path: "/expected",
        outcome: .response(RawResponse(data: Data("ok".utf8), statusCode: 200))
      )
    ]
  )

  await #expect(throws: NetworkError.self) {
    _ = try await transport.send(
      PreparedRequest(
        url: URL(string: "https://example.com/unexpected")!,
        method: .get,
        timeout: .seconds(1)
      )
    )
  }

  let report = await transport.report(generatedAt: Date(timeIntervalSince1970: 0))

  #expect(report.violations.contains { $0.kind == .mismatch })
  #expect(report.violations.contains { $0.kind == .unusedExpectation })
}

@Test func cassetteCanCreateContractExpectations() async throws {
  let cassette = HTTPCassette(
    exchanges: [
      RecordedExchange(
        request: RecordedRequest(
          method: "GET",
          url: "https://example.com/items/1",
          headers: [RecordedHeader(name: "authorization", value: "<redacted>")],
          timeoutMilliseconds: 1_000,
          bodyWasRedacted: true
        ),
        duration: .milliseconds(10),
        outcome: .success(
          RecordedResponse(
            statusCode: 200,
            bodyBase64: Data("one".utf8).base64EncodedString()
          )
        )
      )
    ]
  )

  let transport = try ContractTransport(cassette: cassette)
  var headers = HTTPFields()
  headers[.authorization] = "Bearer runtime-token"

  let response = try await transport.send(
    PreparedRequest(
      url: URL(string: "https://example.com/items/1")!,
      method: .get,
      headers: headers,
      body: Data("different redacted body".utf8),
      timeout: .seconds(1)
    )
  )

  #expect(String(decoding: response.data, as: UTF8.self) == "one")
  try await transport.verifyComplete()
}

@Test func cassetteContractsRejectInvalidRecordedFailureBodies() throws {
  let cassette = HTTPCassette(
    exchanges: [
      RecordedExchange(
        request: RecordedRequest(
          method: "GET",
          url: "https://example.com/items/1",
          timeoutMilliseconds: 1_000
        ),
        duration: .milliseconds(10),
        outcome: .failure(
          RecordedNetworkError(
            kind: .http,
            statusCode: 500,
            bodyBase64: "not-base64"
          )
        )
      )
    ]
  )

  #expect(throws: NetworkError.self) {
    _ = try cassette.contractExpectations()
  }
}

@Test func mockServerWrapsContractsAndExportsReports() async throws {
  let server = MockServer(
    expectations: [
      ContractExpectation(
        id: "scenario-step",
        method: .get,
        path: "/scenario",
        outcome: .response(RawResponse(data: Data("scenario".utf8), statusCode: 200))
      )
    ]
  )

  let response = try await server.send(
    PreparedRequest(
      url: URL(string: "https://example.com/scenario")!,
      method: .get,
      timeout: .seconds(1)
    )
  )

  #expect(String(decoding: response.data, as: UTF8.self) == "scenario")
  try await server.verifyComplete()

  let report = await server.report(generatedAt: Date(timeIntervalSince1970: 0))
  let encoded = try report.encoded()

  #expect(report.passed)
  #expect(String(decoding: encoded, as: UTF8.self).contains(#""expectationID" : "scenario-step""#))
}

@Test func mockServerLatencyHonorsCancellation() async throws {
  let server = MockServer(
    expectations: [
      ContractExpectation(
        id: "slow",
        method: .get,
        path: "/slow",
        outcome: .response(RawResponse(data: Data("slow".utf8), statusCode: 200))
      )
    ],
    latency: .seconds(60)
  )

  let task = Task {
    try await server.send(
      PreparedRequest(
        url: URL(string: "https://example.com/slow")!,
        method: .get,
        timeout: .seconds(1)
      )
    )
  }
  task.cancel()

  await #expect(throws: NetworkError.self) {
    _ = try await task.value
  }
}

@Test func localMockServerServesContractsThroughURLSessionTransport() async throws {
  #if canImport(Network)
  var responseHeaders = HTTPFields()
  responseHeaders[.contentType] = "text/plain; charset=utf-8"

  let server = try await LocalMockServer.start(
    expectations: [
      ContractExpectation(
        id: "get-local",
        method: .get,
        path: "/local",
        query: [ContractQueryExpectation(name: "expand", value: .exact("details"))],
        outcome: .response(
          RawResponse(
            data: Data("local-ok".utf8),
            statusCode: 200,
            headers: responseHeaders
          )
        )
      )
    ]
  )
  defer { server.stop() }

  let client = HTTPClient.live(
    configuration: .default(baseURL: server.baseURL),
    transport: URLSessionTransport()
  )

  let value = try await client.send(LocalMockServerGetRequest())

  #expect(value == "local-ok")
  try await server.verifyComplete()

  let report = await server.report(generatedAt: Date(timeIntervalSince1970: 0))
  #expect(report.passed)
  #expect(report.matches.map(\.expectationID) == ["get-local"])
  #endif
}

@Test func localMockServerServesContractsThroughIPv6BaseURL() async throws {
  #if canImport(Network)
  let server = try await LocalMockServer.start(
    expectations: [
      ContractExpectation(
        id: "get-ipv6-local",
        method: .get,
        path: "/local",
        query: [ContractQueryExpectation(name: "expand", value: .exact("details"))],
        outcome: .response(RawResponse(data: Data("ipv6-ok".utf8), statusCode: 200))
      )
    ],
    host: "::1"
  )
  defer { server.stop() }

  #expect(server.baseURL.absoluteString.hasPrefix("http://[::1]:"))

  let client = HTTPClient.live(
    configuration: .default(baseURL: server.baseURL),
    transport: URLSessionTransport()
  )

  let value = try await client.send(LocalMockServerGetRequest())

  #expect(value == "ipv6-ok")
  try await server.verifyComplete()
  #endif
}

@Test func localMockServerValidatesBodiesFromURLSessionTransport() async throws {
  #if canImport(Network)
  let server = try await LocalMockServer.start(
    expectations: [
      ContractExpectation(
        id: "post-local",
        method: .post,
        path: "/local",
        headers: [ContractHeaderExpectation(name: "content-type", value: .exact("text/plain"))],
        body: .exact(Data("payload".utf8)),
        outcome: .response(RawResponse(data: Data("posted".utf8), statusCode: 201))
      )
    ]
  )
  defer { server.stop() }

  let client = HTTPClient.live(
    configuration: .default(baseURL: server.baseURL),
    transport: URLSessionTransport()
  )

  let value = try await client.send(LocalMockServerPostRequest())

  #expect(value == "posted")
  try await server.verifyComplete()
  #endif
}

@Test func localMockServerReportsHTTPContractViolations() async throws {
  #if canImport(Network)
  let server = try await LocalMockServer.start(
    expectations: [
      ContractExpectation(
        id: "expected",
        method: .get,
        path: "/expected",
        outcome: .response(RawResponse(data: Data("ok".utf8), statusCode: 200))
      )
    ]
  )
  defer { server.stop() }

  let client = HTTPClient.live(
    configuration: .default(baseURL: server.baseURL),
    transport: URLSessionTransport()
  )

  await #expect(throws: NetworkError.self) {
    _ = try await client.send(LocalMockServerGetRequest())
  }

  let report = await server.report(generatedAt: Date(timeIntervalSince1970: 0))

  #expect(!report.passed)
  #expect(report.violations.contains { $0.kind == .mismatch })
  #expect(report.violations.contains { $0.kind == .unusedExpectation })
  #endif
}
