import Foundation
import HTTPTypes
import Testing
@testable import Comet

private struct TestRequest<Response: Sendable>: APIRequest {
  let path: Path
  let method: HTTPMethod
  let responseSerializer: ResponseSerializer<Response>
  var headers: HTTPFields = .init()
  var queryItems: [QueryItem] = []
  var body: HTTPBody = .none
  var options: RequestOptions = .init()
}

private struct TestAPIError: Codable, Sendable, Equatable {
  let code: String
  let message: String
}

private struct TypedErrorRequest: APIRequestWithErrorResponse {
  typealias Response = String
  typealias ErrorResponse = TestAPIError

  let path: Path = "typed-error"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()
  let errorResponseSerializer: ErrorResponseSerializer<TestAPIError> = .json(TestAPIError.self)
}

private struct TestTransport: HTTPTransport, Sendable {
  let handler: @Sendable (PreparedRequest) async throws(NetworkError) -> RawResponse

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    try await self.handler(request)
  }
}

private actor WaitingTransport: HTTPTransport {
  private var sendCount = 0
  private var continuations: [CheckedContinuation<RawResponse, Error>] = []

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    self.sendCount += 1
    do {
      return try await withCheckedThrowingContinuation { continuation in
        self.continuations.append(continuation)
      }
    } catch {
      throw .from(error)
    }
  }

  func count() -> Int {
    self.sendCount
  }

  func resolveAll(with result: Result<RawResponse, NetworkError>) {
    let continuations = self.continuations
    self.continuations.removeAll()

    for continuation in continuations {
      switch result {
      case .success(let response):
        continuation.resume(returning: response)
      case .failure(let error):
        continuation.resume(throwing: error)
      }
    }
  }
}

private actor SequenceTransportState {
  private var results: [Result<RawResponse, NetworkError>]
  private var callCount = 0

  init(results: [Result<RawResponse, NetworkError>]) {
    self.results = results
  }

  func next() throws(NetworkError) -> RawResponse {
    self.callCount += 1
    precondition(!self.results.isEmpty, "No more transport results configured.")
    return try self.results.removeFirst().get()
  }

  func count() -> Int {
    self.callCount
  }
}

private struct SequenceTransport: HTTPTransport, Sendable {
  let state: SequenceTransportState

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    try await self.state.next()
  }
}

private actor ScriptedTransportState {
  private var responses: [RawResponse]
  private var requests: [PreparedRequest] = []

  init(responses: [RawResponse]) {
    self.responses = responses
  }

  func next(request: PreparedRequest) -> RawResponse {
    self.requests.append(request)
    precondition(!self.responses.isEmpty, "No more transport responses configured.")
    return self.responses.removeFirst()
  }

  func count() -> Int {
    self.requests.count
  }

  func request(at index: Int) -> PreparedRequest? {
    guard self.requests.indices.contains(index) else { return nil }
    return self.requests[index]
  }
}

private struct ScriptedTransport: HTTPTransport, Sendable {
  let state: ScriptedTransportState

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    await self.state.next(request: request)
  }
}

private actor CacheCountingTransportState {
  private var callCount = 0

  func next() -> RawResponse {
    self.callCount += 1
    var headers = HTTPFields()
    headers[HTTPField.Name("Cache-Control")!] = "max-age=60"
    return RawResponse(
      data: Data("network-\(self.callCount)".utf8),
      statusCode: 200,
      headers: headers
    )
  }

  func count() -> Int {
    self.callCount
  }
}

private struct CacheCountingTransport: HTTPTransport, Sendable {
  let state: CacheCountingTransportState

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    await self.state.next()
  }
}

private actor AuthTestStore {
  private var tokenValue: String?
  private var refreshToken: String
  private var refreshCountValue = 0
  private let refreshDelay: Duration

  init(
    token: String?,
    refreshToken: String,
    refreshDelay: Duration = .zero
  ) {
    self.tokenValue = token
    self.refreshToken = refreshToken
    self.refreshDelay = refreshDelay
  }

  func token() -> String? {
    self.tokenValue
  }

  func refresh() async -> String? {
    self.refreshCountValue += 1
    if self.refreshDelay > .zero {
      try? await Task.sleep(for: self.refreshDelay)
    }
    self.tokenValue = self.refreshToken
    return self.refreshToken
  }

  func refreshCount() -> Int {
    self.refreshCountValue
  }
}

private actor AuthTransportState {
  private var responses: [RawResponse]
  private var authorizationValues: [String?] = []

  init(responses: [RawResponse]) {
    self.responses = responses
  }

  func next(request: PreparedRequest) -> RawResponse {
    self.authorizationValues.append(request.headers[.authorization])
    precondition(!self.responses.isEmpty, "No more auth transport responses configured.")
    return self.responses.removeFirst()
  }

  func authorizations() -> [String?] {
    self.authorizationValues
  }
}

private struct AuthTransport: HTTPTransport, Sendable {
  let state: AuthTransportState

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    await self.state.next(request: request)
  }
}

private struct StaticStreamingTransport: HTTPStreamingTransport, HTTPProgressTransport, Sendable {
  let response: RawResponse

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    self.response
  }

  func stream(
    _ request: PreparedRequest,
    chunkSize: Int
  ) -> AsyncThrowingStream<HTTPStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(
        .response(
          HTTPStreamResponse(
            statusCode: self.response.statusCode,
            headers: self.response.headers
          )
        )
      )
      let resolvedChunkSize = max(1, chunkSize)
      var offset = 0
      while offset < self.response.data.count {
        let end = min(offset + resolvedChunkSize, self.response.data.count)
        continuation.yield(.bytes(self.response.data.subdata(in: offset..<end)))
        offset = end
      }
      continuation.yield(.complete)
      continuation.finish()
    }
  }

  func send(
    _ request: PreparedRequest,
    progress: @escaping @Sendable (TransferProgress) async -> Void
  ) async throws(NetworkError) -> RawResponse {
    if let body = request.body {
      await progress(
        TransferProgress(
          kind: .upload,
          completedBytes: Int64(body.count),
          totalBytes: Int64(body.count)
        )
      )
    }
    await progress(
      TransferProgress(
        kind: .download,
        completedBytes: Int64(self.response.data.count),
        totalBytes: Int64(self.response.data.count)
      )
    )
    return self.response
  }
}

private actor CountingStreamingTransportState {
  private var streamCount = 0

  func recordStream() {
    self.streamCount += 1
  }

  func count() -> Int {
    self.streamCount
  }
}

private struct CountingStreamingTransport: HTTPStreamingTransport, Sendable {
  let state: CountingStreamingTransportState
  let response: RawResponse

  func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    self.response
  }

  func stream(
    _ request: PreparedRequest,
    chunkSize: Int
  ) -> AsyncThrowingStream<HTTPStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        await self.state.recordStream()
        continuation.yield(
          .response(
            HTTPStreamResponse(
              statusCode: self.response.statusCode,
              headers: self.response.headers
            )
          )
        )
        if !self.response.data.isEmpty {
          continuation.yield(.bytes(self.response.data))
        }
        continuation.yield(.complete)
        continuation.finish()
      }
    }
  }
}

private actor ProgressRecorder {
  private var values: [TransferProgress] = []

  func record(_ progress: TransferProgress) {
    self.values.append(progress)
  }

  func snapshot() -> [TransferProgress] {
    self.values
  }
}

private final class LogSink: @unchecked Sendable {
  private let lock = NSLock()
  private var messages: [String] = []

  func append(_ message: String) {
    self.lock.lock()
    defer { self.lock.unlock() }
    self.messages.append(message)
  }

  func snapshot() -> [String] {
    self.lock.lock()
    defer { self.lock.unlock() }
    return self.messages
  }
}

private actor SleepRecorder {
  private var durations: [Duration] = []

  func record(_ duration: Duration) {
    self.durations.append(duration)
  }

  func snapshot() -> [Duration] {
    self.durations
  }
}

private actor FinishRecorder {
  private var values: [String] = []

  func record(_ result: Result<RawResponse, NetworkError>) {
    switch result {
    case .success(let response):
      self.values.append("success:\(response.statusCode)")
    case .failure(let error):
      self.values.append("failure:\(error.debugSummary)")
    }
  }

  func snapshot() -> [String] {
    self.values
  }
}

private struct FinishRecordingMiddleware: Middleware {
  let recorder: FinishRecorder

  func finish(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async {
    await self.recorder.record(result)
  }
}

private func durationMilliseconds(_ duration: Duration) -> Int64 {
  let components = duration.components
  return components.seconds * 1_000
    + Int64(Double(components.attoseconds) / 1_000_000_000_000_000)
}

private func cacheControlHeaders(_ value: String) -> HTTPFields {
  var headers = HTTPFields()
  headers[HTTPField.Name("Cache-Control")!] = value
  return headers
}

@Test func pathBuildsEncodedSegments() {
  let path: Path = "users"
  let built = path / "has space" / 42

  #expect(built.rawValue == "users/has%20space/42")
}

@Test func queryItemHelpersCoverCommonEncodings() {
  let date = Date(timeIntervalSince1970: 1_700_000_000.123)
  let items = QueryItems {
    QueryItem("search", "comet")
    QueryItem("page", 2)
    QueryItem("missing", Optional<String>.none)
    QueryItem.optional("limit", Optional(25))
    QueryItem.flag("debug", isEnabled: true)
    QueryItem.flag("disabled", isEnabled: false)
    QueryItem.bool("includeArchived", false)
    QueryItem.items("tag", values: ["swift", "networking"])
    QueryItem.joined("ids", values: [1, 2, 3])
    QueryItem.date("createdAfter", date, style: .secondsSince1970)
    [
      QueryItem.optional("optionalArray", Optional("included")),
      QueryItem.optional("emptyArray", Optional<String>.none)
    ]
  }

  let expectedItems = [
    QueryItem("search", "comet"),
    QueryItem("page", "2"),
    QueryItem("limit", "25"),
    QueryItem("debug", "true"),
    QueryItem("includeArchived", "false"),
    QueryItem("tag", "swift"),
    QueryItem("tag", "networking"),
    QueryItem("ids", "1,2,3"),
    QueryItem("createdAfter", "1700000000"),
    QueryItem("optionalArray", "included")
  ]

  #expect(items == expectedItems)

  #expect(QueryItem.date("createdAt", Date(timeIntervalSince1970: 0)).value == "1970-01-01T00:00:00Z")
  #expect(QueryItem.date("createdAt", date, style: .millisecondsSince1970).value == "1700000000123")
  #expect(QueryItem.joined("empty", values: [Int]()) == nil)
}

@Test func requestBuilderUsesAbsoluteURLWithoutBaseVersion() throws {
  let configuration = ClientConfiguration.default(baseURL: URL(string: "https://api.example.com")!)
  let request = TestRequest(
    path: "ignored",
    method: .get,
    responseSerializer: .data,
    queryItems: [QueryItem("hello", "world")],
    options: RequestOptions(
      apiVersion: "v9",
      absoluteURL: URL(string: "https://cdn.example.com/files/test")!
    )
  )

  let prepared = try RequestBuilder.build(request, configuration: configuration)

  #expect(prepared.url.absoluteString == "https://cdn.example.com/files/test?hello=world")
}

@Test func requestBuilderEncodesBasePathAndAPIVersionWithoutDoubleEncodingRequestPath() throws {
  let configuration = ClientConfiguration.default(baseURL: URL(string: "https://api.example.com/root%20path/root%2Fencoded")!)
  let request = TestRequest(
    path: "has space" / "already%encoded",
    method: .get,
    responseSerializer: .data,
    options: RequestOptions(apiVersion: "v 1")
  )

  let prepared = try RequestBuilder.build(request, configuration: configuration)

  #expect(prepared.url.absoluteString == "https://api.example.com/root%20path/root%2Fencoded/v%201/has%20space/already%25encoded")
}

@Test func httpClientCanPrepareRequestsForInspection() throws {
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://api.example.com")!),
    transport: TestTransport { _ in RawResponse(data: Data(), statusCode: 200) }
  )
  let request = TestRequest(
    path: "inspect",
    method: .post,
    responseSerializer: .data,
    headers: HeaderFields {
      HTTPField(name: .contentType, value: "application/json")
    },
    body: .json(["name": "Comet"]),
    options: RequestOptions(timeout: .seconds(7))
  )

  let prepared = try client.prepare(request)

  #expect(prepared.url.absoluteString == "https://api.example.com/inspect")
  #expect(prepared.method == .post)
  #expect(prepared.timeout == .seconds(7))
  #expect(prepared.headers[.contentType] == "application/json")
  #expect(prepared.curlCommand().contains("https://api.example.com/inspect"))
}

@Test func requestOptionsDefaultToNoAPIVersionPrefix() {
  #expect(RequestOptions().apiVersion == nil)
}

@Test func requestBuilderCarriesMetadataAndRedactionPolicy() throws {
  let configuration = ClientConfiguration.default(baseURL: URL(string: "https://example.com")!)
  let policy = RedactionPolicy(redactedHeaders: ["x-secret"])
  let metadata = RequestMetadata(name: "GetSecret", tags: ["secrets"], operationID: "getSecret")
  let request = TestRequest(
    path: "secret",
    method: .get,
    responseSerializer: .data,
    options: RequestOptions(
      metadata: metadata,
      redactionPolicy: policy
    )
  )

  let prepared = try RequestBuilder.build(request, configuration: configuration)

  #expect(prepared.metadata == metadata)
  #expect(prepared.redactionPolicy.redacts(headerName: "X-Secret"))
}

@Test func requestBuilderPreservesRepeatedHeaders() throws {
  var defaultHeaders = HTTPFields()
  defaultHeaders[values: .accept] = ["text/html"]

  let configuration = ClientConfiguration(
    baseURL: URL(string: "https://example.com")!,
    defaultHeaders: defaultHeaders
  )
  let request = TestRequest(
    path: "headers",
    method: .get,
    responseSerializer: .data,
    headers: HeaderFields {
      HTTPField(name: .accept, value: "application/json")
      HTTPField(name: .accept, value: "text/plain")
    }
  )

  let prepared = try RequestBuilder.build(request, configuration: configuration)

  #expect(prepared.headers[fields: .accept].map(\.value) == ["application/json", "text/plain"])
}

@Test func httpClientSendsAndSerializesJSON() async throws {
  struct Payload: Codable, Sendable, Equatable { let id: Int }

  let payload = Payload(id: 42)
  let data = try ClientConfiguration.defaultJSONEncoder().encode(payload)

  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: TestTransport { _ in
      RawResponse(data: data, statusCode: 200)
    }
  )

  let request = TestRequest(
    path: "todos/42",
    method: .get,
    responseSerializer: .json(Payload.self)
  )

  let response = try await client.send(request)
  #expect(response == payload)
}

@Test func httpClientAllowsCustomStatusValidation() async throws {
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: TestTransport { _ in
      RawResponse(data: Data("cached".utf8), statusCode: 304)
    }
  )

  let request = TestRequest(
    path: "cached",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(statusValidation: .codes(304))
  )

  let response = try await client.send(request)
  #expect(response == "cached")
}

@Test func statusValidationPresetsCoverCommonHTTPCases() {
  #expect(StatusValidation.successOrNotModified.contains(200))
  #expect(StatusValidation.successOrNotModified.contains(304))
  #expect(!StatusValidation.successOrNotModified.contains(404))

  #expect(StatusValidation.successAndRedirects.contains(302))
  #expect(!StatusValidation.successAndRedirects.contains(400))

  #expect(StatusValidation.noContent.contains(204))
  #expect(StatusValidation.noContent.contains(205))
  #expect(!StatusValidation.noContent.contains(200))
}

@Test func httpClientThrowsHTTPErrorOnNonSuccessStatus() async {
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: TestTransport { _ in
      RawResponse(data: Data("nope".utf8), statusCode: 500)
    }
  )

  let request = TestRequest(
    path: "broken",
    method: .get,
    responseSerializer: .string()
  )

  await #expect(throws: NetworkError.self) {
    _ = try await client.send(request)
  }
}

@Test func httpClientDecodesRequestDeclaredTypedErrorResponses() async throws {
  let errorBody = TestAPIError(code: "validation_failed", message: "Name is required.")
  let data = try ClientConfiguration.defaultJSONEncoder().encode(errorBody)
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: TestTransport { _ in
      RawResponse(data: data, statusCode: 422)
    }
  )

  do {
    _ = try await client.sendWithTypedErrors(TypedErrorRequest())
    Issue.record("Expected a typed API client error.")
  } catch {
    guard case .api(let response) = error else {
      Issue.record("Expected a decoded API error, got \(error).")
      return
    }

    #expect(response.statusCode == 422)
    #expect(response.body == errorBody)
    #expect(response.rawBody == data)
    #expect(response.networkError.statusCode == 422)
    #expect(error.decodedErrorBody == errorBody)
    #expect(error.statusCode == 422)
  }
}

@Test func httpClientDecodesTypedErrorResponsesFromCallSiteSerializer() async throws {
  let errorBody = TestAPIError(code: "missing", message: "Todo was not found.")
  let data = try ClientConfiguration.defaultJSONEncoder().encode(errorBody)
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: TestTransport { _ in
      RawResponse(data: data, statusCode: 404)
    }
  )
  let request = TestRequest(
    path: "todos/404",
    method: .get,
    responseSerializer: ResponseSerializer<String>.string()
  )

  do {
    _ = try await client.send(
      request,
      errorResponseSerializer: .json(TestAPIError.self)
    )
    Issue.record("Expected a typed API client error.")
  } catch {
    #expect(error.decodedErrorBody == errorBody)
    #expect(error.networkError.statusCode == 404)
  }
}

@Test func httpClientPreservesRawHTTPErrorWhenTypedErrorDecodingFails() async {
  let data = Data("not-json".utf8)
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: TestTransport { _ in
      RawResponse(data: data, statusCode: 500)
    }
  )
  let request = TestRequest(
    path: "broken",
    method: .get,
    responseSerializer: ResponseSerializer<String>.string()
  )

  do {
    _ = try await client.send(
      request,
      errorResponseSerializer: .json(TestAPIError.self)
    )
    Issue.record("Expected a typed API client error.")
  } catch {
    guard case .errorResponseDecodingFailed(let networkError, let decodingError) = error else {
      Issue.record("Expected an error decoding failure, got \(error).")
      return
    }

    #expect(networkError.statusCode == 500)
    #expect(networkError.bodyData == data)
    guard case .decoding = decodingError else {
      Issue.record("Expected a decoding error, got \(decodingError).")
      return
    }
  }
}

@Test func responseSerializerSupportsEmptyResponses() async throws {
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: TestTransport { _ in
      RawResponse(data: Data(), statusCode: 204)
    }
  )

  let request = TestRequest(
    path: "empty",
    method: .get,
    responseSerializer: .empty
  )

  _ = try await client.send(request)
}

@Test func stringSerializerUsesCharsetFromResponseHeaders() throws {
  let response = RawResponse(
    data: Data([0x63, 0x61, 0x66, 0xE9]),
    statusCode: 200,
    headers: {
      var headers = HTTPFields()
      headers[.contentType] = "text/plain; charset=iso-8859-1"
      return headers
    }()
  )

  let string = try ResponseSerializer<String>.string().serialize(
    response,
    .default(baseURL: URL(string: "https://example.com")!)
  )

  #expect(string == "café")
}

@Test func stringSerializerPrefersExplicitEncodingWhenProvided() throws {
  let response = RawResponse(
    data: Data("hello".utf8),
    statusCode: 200,
    headers: {
      var headers = HTTPFields()
      headers[.contentType] = "text/plain; charset=iso-8859-1"
      return headers
    }()
  )

  let string = try ResponseSerializer<String>.string(encoding: .utf8).serialize(
    response,
    .default(baseURL: URL(string: "https://example.com")!)
  )

  #expect(string == "hello")
}

@Test func retryMiddlewareUsesInjectedRandomnessAndEmitsEvents() async throws {
  let transportState = SequenceTransportState(results: [
    .failure(.timeout),
    .success(RawResponse(data: Data("ok".utf8), statusCode: 200))
  ])
  let sleepRecorder = SleepRecorder()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        RetryMiddleware(
          maxAttempts: 2,
          backoff: .constant(.seconds(1)),
          jitter: 0.5
        )
      ],
      sleep: { duration in
        await sleepRecorder.record(duration)
      },
      randomDouble: { range in
        range.upperBound
      }
    ),
    transport: SequenceTransport(state: transportState)
  )

  var iterator = client.activity.makeAsyncIterator()
  let request = TestRequest(
    path: "retry",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(metadata: RequestMetadata(name: "RetryProof", tags: ["retries"]))
  )

  let response = try await client.send(request)
  let events = await [iterator.next(), iterator.next(), iterator.next()].compactMap { $0 }

  #expect(response == "ok")
  #expect(await transportState.count() == 2)
  #expect(await sleepRecorder.snapshot().map(durationMilliseconds) == [1_500])
  #expect(events.count == 3)

  guard case .requestStarted(_, _, _, let startedMetadata) = events[0] else {
    Issue.record("Expected requestStarted as the first activity event.")
    return
  }
  #expect(startedMetadata.displayName == "RetryProof")

  guard case .requestRetried(_, let attempt, let delay, let retryMetadata) = events[1] else {
    Issue.record("Expected requestRetried as the second activity event.")
    return
  }
  #expect(attempt == 1)
  #expect(durationMilliseconds(delay) == 1_500)
  #expect(retryMetadata.tags == ["retries"])

  guard case .requestCompleted(_, let statusCode, _, let completedMetadata) = events[2] else {
    Issue.record("Expected requestCompleted as the third activity event.")
    return
  }
  #expect(statusCode == 200)
  #expect(completedMetadata.displayName == "RetryProof")
}

@Test func requestTraceRecordsAttemptsRetriesAndResult() async throws {
  let transportState = SequenceTransportState(results: [
    .failure(.timeout),
    .success(RawResponse(data: Data("ok".utf8), statusCode: 200))
  ])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        RetryMiddleware(
          maxAttempts: 2,
          backoff: .constant(.seconds(1)),
          jitter: 0
        )
      ],
      sleep: { _ in }
    ),
    transport: SequenceTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "trace",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(metadata: RequestMetadata(name: "TraceProof", tags: ["traces"]))
  )

  let response = try await client.send(request)
  let trace = try #require(await traces.next())

  #expect(response == "ok")
  #expect(trace.metadata.displayName == "TraceProof")
  #expect(trace.method == .get)
  #expect(trace.url.absoluteString == "https://example.com/trace")
  #expect(trace.attempts.count == 2)
  #expect(trace.attempts[0].number == 1)
  #expect(trace.attempts[0].error?.isTimeoutError == true)
  #expect(trace.attempts[0].retryDelay == .seconds(1))
  #expect(trace.attempts[1].number == 2)
  #expect(trace.attempts[1].responseStatusCode == 200)
  #expect(trace.attempts[1].responseBytes == 2)
  #expect(trace.statusCode == 200)
  #expect(trace.responseBytes == 2)
  #expect(trace.error == nil)
  #expect(trace.diagnosticSummary.contains("TraceProof"))
}

@Test func middlewareFinishRunsOnceAfterTerminalRetryResult() async throws {
  let recorder = FinishRecorder()
  let transportState = SequenceTransportState(results: [
    .failure(.timeout),
    .success(RawResponse(data: Data("ok".utf8), statusCode: 200))
  ])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        RetryMiddleware(maxAttempts: 2),
        FinishRecordingMiddleware(recorder: recorder)
      ],
      sleep: { _ in }
    ),
    transport: SequenceTransport(state: transportState)
  )

  let response = try await client.send(
    TestRequest(
      path: "finish",
      method: .get,
      responseSerializer: .string()
    )
  )

  #expect(response == "ok")
  #expect(await recorder.snapshot() == ["success:200"])
}

@Test func traceContextParsesRendersAndRejectsInvalidTraceparents() throws {
  let traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  let context = try #require(TraceContext(traceparent: traceparent))

  #expect(context.version == "00")
  #expect(context.traceID == "4bf92f3577b34da6a3ce929d0e0e4736")
  #expect(context.parentID == "00f067aa0ba902b7")
  #expect(context.flags == "01")
  #expect(context.traceparent == traceparent)
  #expect(context.isSampled)

  #expect(TraceContext(traceparent: "00-00000000000000000000000000000000-00f067aa0ba902b7-01") == nil)
  #expect(TraceContext(traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01") == nil)
  #expect(TraceContext(traceparent: "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01") == nil)
  #expect(TraceContext(traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-0z") == nil)
}

@Test func tracePropagationMiddlewareInjectsMetadataTraceContext() async throws {
  let traceContext = try #require(
    TraceContext(
      traceID: "4bf92f3577b34da6a3ce929d0e0e4736",
      parentID: "00f067aa0ba902b7",
      flags: "01"
    )
  )
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [TracePropagationMiddleware()]
    ),
    transport: TestTransport { request in
      #expect(request.headers[TraceContext.traceparentHeaderName] == traceContext.traceparent)
      return RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )
  let request = TestRequest(
    path: "trace",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(
      metadata: RequestMetadata(
        name: "TraceHeader",
        operationID: "trace.header",
        traceContext: traceContext
      )
    )
  )

  let response = try await client.send(request)

  #expect(response == "ok")
  #expect(request.options.metadata.operationName == "trace.header")
  #expect(request.options.metadata.traceID == traceContext.traceID)
}

@Test func tracePropagationMiddlewareGeneratesTraceContextFromRequestID() async throws {
  let requestID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
  let expectedContext = TraceContext.generated(requestID: requestID)
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [TracePropagationMiddleware()],
      makeRequestID: { requestID }
    ),
    transport: TestTransport { request in
      #expect(request.headers[TraceContext.traceparentHeaderName] == expectedContext.traceparent)
      return RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )

  let response = try await client.send(
    TestRequest(
      path: "generated-trace",
      method: .get,
      responseSerializer: .string()
    )
  )

  #expect(response == "ok")
  #expect(expectedContext.traceID == "0123456789abcdef0123456789abcdef")
}

@Test func tracePropagationMiddlewarePreservesExistingTraceparentByDefault() async throws {
  let existingTraceparent = "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-00"
  var headers = HTTPFields()
  headers[TraceContext.traceparentHeaderName] = existingTraceparent

  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [TracePropagationMiddleware()]
    ),
    transport: TestTransport { request in
      #expect(request.headers[TraceContext.traceparentHeaderName] == existingTraceparent)
      return RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )

  let response = try await client.send(
    TestRequest(
      path: "existing-trace",
      method: .get,
      responseSerializer: .string(),
      headers: headers
    )
  )

  #expect(response == "ok")
}

@Test func tracePropagationMiddlewareCanReplaceExistingTraceparent() async throws {
  let replacementContext = try #require(
    TraceContext(
      traceID: "4bf92f3577b34da6a3ce929d0e0e4736",
      parentID: "00f067aa0ba902b7",
      flags: "01"
    )
  )
  var headers = HTTPFields()
  headers[TraceContext.traceparentHeaderName] = "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-00"

  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [TracePropagationMiddleware(replacesExistingHeader: true)]
    ),
    transport: TestTransport { request in
      #expect(request.headers[TraceContext.traceparentHeaderName] == replacementContext.traceparent)
      return RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )

  let response = try await client.send(
    TestRequest(
      path: "replaced-trace",
      method: .get,
      responseSerializer: .string(),
      headers: headers,
      options: RequestOptions(
        metadata: RequestMetadata(traceContext: replacementContext)
      )
    )
  )

  #expect(response == "ok")
}

@Test func requestTraceRecordsPropagatedTraceIDWithoutTracestate() async throws {
  let requestID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
  let expectedContext = TraceContext.generated(requestID: requestID)
  var headers = HTTPFields()
  headers[HTTPField.Name("tracestate")!] = "vendor=super-secret"

  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [TracePropagationMiddleware()],
      makeRequestID: { requestID }
    ),
    transport: TestTransport { _ in
      RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )
  var traces = client.traces.makeAsyncIterator()

  let response = try await client.send(
    TestRequest(
      path: "recorded-trace",
      method: .get,
      responseSerializer: .string(),
      headers: headers
    )
  )
  let trace = try #require(await traces.next())

  #expect(response == "ok")
  #expect(trace.traceID == expectedContext.traceID)
  #expect(trace.traceContext?.traceparent == expectedContext.traceparent)
  #expect(trace.diagnosticSummary.contains(expectedContext.traceID))
  #expect(!trace.diagnosticSummary.contains("super-secret"))
}

@Test func cacheMiddlewareReturnsCachedSafeMethodResponses() async throws {
  let store = MemoryHTTPCacheStore()
  let transportState = CacheCountingTransportState()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: CacheCountingTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )

  let first = try await client.send(request)
  let firstTrace = try #require(await traces.next())
  let second = try await client.send(request)
  let secondTrace = try #require(await traces.next())

  #expect(first == "network-1")
  #expect(second == "network-1")
  #expect(await transportState.count() == 1)
  #expect(await store.count == 1)
  #expect(firstTrace.cacheEvents.map(\.kind) == [.miss, .store])
  #expect(secondTrace.cacheEvents.map(\.kind) == [.hit, .skippedStore])
}

@Test func cacheMiddlewareBypassesUnsafeMethodsByDefault() async throws {
  let store = MemoryHTTPCacheStore()
  let transportState = CacheCountingTransportState()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: CacheCountingTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "cache",
    method: .post,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )

  let first = try await client.send(request)
  let firstTrace = try #require(await traces.next())
  let second = try await client.send(request)
  let secondTrace = try #require(await traces.next())

  #expect(first == "network-1")
  #expect(second == "network-2")
  #expect(await transportState.count() == 2)
  #expect(await store.count == 0)
  #expect(firstTrace.cacheEvents.map(\.reason) == [.unsafeMethod, .unsafeMethod])
  #expect(secondTrace.cacheEvents.map(\.reason) == [.unsafeMethod, .unsafeMethod])
}

@Test func cacheMiddlewareReloadIgnoringCacheStoresReplacementResponse() async throws {
  let store = MemoryHTTPCacheStore()
  let transportState = CacheCountingTransportState()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: CacheCountingTransport(state: transportState)
  )
  let cachedRequest = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )
  let reloadRequest = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .reloadIgnoringCache)
  )

  let first = try await client.send(cachedRequest)
  let second = try await client.send(reloadRequest)
  let third = try await client.send(cachedRequest)

  #expect(first == "network-1")
  #expect(second == "network-2")
  #expect(third == "network-2")
  #expect(await transportState.count() == 2)
}

@Test func cacheMetadataParsesFreshnessAndValidators() throws {
  var headers = HTTPFields()
  headers[HTTPField.Name("Cache-Control")!] = "max-age=60, must-revalidate"
  headers[HTTPField.Name("Expires")!] = "Wed, 21 Oct 2015 07:28:00 GMT"
  headers[HTTPField.Name("ETag")!] = #""v1""#
  headers[HTTPField.Name("Last-Modified")!] = "Wed, 21 Oct 2015 07:20:00 GMT"
  let storedAt = Date(timeIntervalSince1970: 1_445_412_420)

  let metadata = HTTPCacheMetadata(headers: headers, storedAt: storedAt)

  #expect(metadata.cacheControl.maxAgeSeconds == 60)
  #expect(metadata.cacheControl.mustRevalidate)
  #expect(metadata.eTag == #""v1""#)
  #expect(metadata.lastModified != nil)
  #expect(metadata.isFresh(at: storedAt.addingTimeInterval(30)))
  #expect(!metadata.isFresh(at: storedAt.addingTimeInterval(61)))
  #expect(metadata.conditionalHeaders()[HTTPField.Name("If-None-Match")!] == #""v1""#)
  #expect(metadata.conditionalHeaders()[HTTPField.Name("If-Modified-Since")!] == "Wed, 21 Oct 2015 07:20:00 GMT")
}

@Test func cacheMetadataHonorsAgeSharedMaxAgeAndDefaultFreshness() throws {
  var headers = HTTPFields()
  headers[HTTPField.Name("Cache-Control")!] = "max-age=60, s-maxage=10, stale-if-error=30, proxy-revalidate"
  headers[HTTPField.Name("Age")!] = "5"
  let storedAt = Date(timeIntervalSince1970: 100)
  let metadata = HTTPCacheMetadata(headers: headers, storedAt: storedAt)

  #expect(metadata.cacheControl.sharedMaxAgeSeconds == 10)
  #expect(metadata.cacheControl.staleIfErrorSeconds == 30)
  #expect(metadata.cacheControl.proxyRevalidate)
  #expect(metadata.isFresh(at: storedAt.addingTimeInterval(50), isShared: false))
  #expect(!metadata.isFresh(at: storedAt.addingTimeInterval(6), isShared: true))
  #expect(metadata.canServeStaleIfError(at: storedAt.addingTimeInterval(20), isShared: true))
  #expect(!metadata.canServeStaleIfError(at: storedAt.addingTimeInterval(40), isShared: true))

  let implicit = HTTPCacheMetadata(storedAt: storedAt)
  #expect(!implicit.isFresh(at: storedAt.addingTimeInterval(1)))
  #expect(implicit.isFresh(at: storedAt.addingTimeInterval(1), defaultFreshnessLifetime: .seconds(30)))
}

@Test func cacheMiddlewareSkipsResponsesWithoutFreshnessOrValidators() async throws {
  let transportState = ScriptedTransportState(
    responses: [
      RawResponse(data: Data("first".utf8), statusCode: 200),
      RawResponse(data: Data("second".utf8), statusCode: 200)
    ]
  )
  let store = MemoryHTTPCacheStore()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: ScriptedTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "implicit",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )

  let first = try await client.send(request)
  let firstTrace = try #require(await traces.next())
  let second = try await client.send(request)
  let secondTrace = try #require(await traces.next())

  #expect(first == "first")
  #expect(second == "second")
  #expect(await transportState.count() == 2)
  #expect(await store.count == 0)
  #expect(firstTrace.cacheEvents.map(\.reason).contains(.noExplicitFreshness))
  #expect(secondTrace.cacheEvents.map(\.reason).contains(.noExplicitFreshness))
}

@Test func cacheMiddlewareUsesDefaultFreshnessLifetimeWhenConfigured() async throws {
  let transportState = ScriptedTransportState(
    responses: [
      RawResponse(data: Data("default-cache".utf8), statusCode: 200)
    ]
  )
  let store = MemoryHTTPCacheStore()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store, now: { Date(timeIntervalSince1970: 10) })]
    ),
    transport: ScriptedTransport(state: transportState)
  )
  let request = TestRequest(
    path: "default-freshness",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(
      cachePolicy: HTTPCachePolicy(
        strategy: .returnCacheElseLoad,
        defaultFreshnessLifetime: .seconds(60)
      )
    )
  )

  let first = try await client.send(request)
  let second = try await client.send(request)

  #expect(first == "default-cache")
  #expect(second == "default-cache")
  #expect(await transportState.count() == 1)
  #expect(await store.count == 1)
}

@Test func cacheMiddlewareRevalidatesStaleResponsesWithETagAndMerges304() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  var cachedHeaders = HTTPFields()
  cachedHeaders[HTTPField.Name("Cache-Control")!] = "max-age=0"
  cachedHeaders[HTTPField.Name("ETag")!] = #""v1""#
  cachedHeaders[.contentType] = "application/json"
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached".utf8),
        statusCode: 200,
        headers: cachedHeaders,
        storedAt: Date(timeIntervalSince1970: 0)
      )
    ]
  )

  var revalidatedHeaders = HTTPFields()
  revalidatedHeaders[HTTPField.Name("Cache-Control")!] = "max-age=60"
  revalidatedHeaders[HTTPField.Name("ETag")!] = #""v1""#
  let transportState = ScriptedTransportState(
    responses: [
      RawResponse(data: Data(), statusCode: 304, headers: revalidatedHeaders)
    ]
  )
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        CacheMiddleware(
          store: store,
          now: { Date(timeIntervalSince1970: 10) }
        )
      ]
    ),
    transport: ScriptedTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )

  let response = try await client.send(request)
  let trace = try #require(await traces.next())
  let sentRequest = try #require(await transportState.request(at: 0))
  let stored = try #require(await store.cachedResponse(for: key))

  #expect(response == "cached")
  #expect(await transportState.count() == 1)
  #expect(sentRequest.headers[HTTPField.Name("If-None-Match")!] == #""v1""#)
  #expect(stored.data == Data("cached".utf8))
  #expect(stored.headers[HTTPField.Name("Cache-Control")!] == "max-age=60")
  #expect(trace.cacheEvents.map(\.kind) == [.stale, .revalidate, .update])
  #expect(trace.cacheEvents.last?.reason == .notModified)
}

@Test func cacheMiddlewareRevalidatesFreshResponsesWithoutStaleTrace() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  var cachedHeaders = HTTPFields()
  cachedHeaders[HTTPField.Name("Cache-Control")!] = "max-age=60"
  cachedHeaders[HTTPField.Name("ETag")!] = #""v1""#
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached".utf8),
        statusCode: 200,
        headers: cachedHeaders,
        storedAt: Date(timeIntervalSince1970: 0)
      )
    ]
  )

  var revalidatedHeaders = HTTPFields()
  revalidatedHeaders[HTTPField.Name("Cache-Control")!] = "max-age=120"
  revalidatedHeaders[HTTPField.Name("ETag")!] = #""v1""#
  let transportState = ScriptedTransportState(
    responses: [
      RawResponse(data: Data(), statusCode: 304, headers: revalidatedHeaders)
    ]
  )
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        CacheMiddleware(
          store: store,
          now: { Date(timeIntervalSince1970: 10) }
        )
      ]
    ),
    transport: ScriptedTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .revalidate)
  )

  let response = try await client.send(request)
  let trace = try #require(await traces.next())
  let sentRequest = try #require(await transportState.request(at: 0))
  let stored = try #require(await store.cachedResponse(for: key))

  #expect(response == "cached")
  #expect(sentRequest.headers[HTTPField.Name("If-None-Match")!] == #""v1""#)
  #expect(stored.headers[HTTPField.Name("Cache-Control")!] == "max-age=120")
  #expect(trace.cacheEvents.map(\.kind) == [.revalidate, .update])
  #expect(trace.cacheEvents.last?.reason == .notModified)
}

@Test func cacheMiddlewareStoresReplacementWhenRevalidationReturns200() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  var cachedHeaders = HTTPFields()
  cachedHeaders[HTTPField.Name("Cache-Control")!] = "max-age=0"
  cachedHeaders[HTTPField.Name("ETag")!] = #""v1""#
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached".utf8),
        statusCode: 200,
        headers: cachedHeaders,
        storedAt: Date(timeIntervalSince1970: 0)
      )
    ]
  )

  var replacementHeaders = HTTPFields()
  replacementHeaders[HTTPField.Name("Cache-Control")!] = "max-age=60"
  replacementHeaders[HTTPField.Name("ETag")!] = #""v2""#
  let transportState = ScriptedTransportState(
    responses: [
      RawResponse(data: Data("replacement".utf8), statusCode: 200, headers: replacementHeaders)
    ]
  )
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        CacheMiddleware(
          store: store,
          now: { Date(timeIntervalSince1970: 10) }
        )
      ]
    ),
    transport: ScriptedTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .revalidate)
  )

  let response = try await client.send(request)
  let trace = try #require(await traces.next())
  let sentRequest = try #require(await transportState.request(at: 0))
  let stored = try #require(await store.cachedResponse(for: key))

  #expect(response == "replacement")
  #expect(sentRequest.headers[HTTPField.Name("If-None-Match")!] == #""v1""#)
  #expect(stored.data == Data("replacement".utf8))
  #expect(stored.headers[HTTPField.Name("ETag")!] == #""v2""#)
  #expect(trace.cacheEvents.map(\.kind) == [.stale, .revalidate, .store])
  #expect(trace.cacheEvents.last?.reason == .replaced)
}

@Test func cacheMiddlewareRefreshesExpiredEntriesWithoutValidators() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  var cachedHeaders = HTTPFields()
  cachedHeaders[HTTPField.Name("Expires")!] = "Wed, 21 Oct 2015 07:28:00 GMT"
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached".utf8),
        statusCode: 200,
        headers: cachedHeaders,
        storedAt: Date(timeIntervalSince1970: 1_445_412_420)
      )
    ]
  )

  let transportState = ScriptedTransportState(
    responses: [
      RawResponse(data: Data("network".utf8), statusCode: 200, headers: cacheControlHeaders("max-age=60"))
    ]
  )
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        CacheMiddleware(
          store: store,
          now: { Date(timeIntervalSince1970: 1_445_412_481) }
        )
      ]
    ),
    transport: ScriptedTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )

  let response = try await client.send(request)
  let trace = try #require(await traces.next())
  let sentRequest = try #require(await transportState.request(at: 0))
  let stored = try #require(await store.cachedResponse(for: key))

  #expect(response == "network")
  #expect(sentRequest.headers[HTTPField.Name("If-None-Match")!] == nil)
  #expect(sentRequest.headers[HTTPField.Name("If-Modified-Since")!] == nil)
  #expect(stored.data == Data("network".utf8))
  #expect(trace.cacheEvents.map(\.kind) == [.stale, .revalidate, .store])
  #expect(trace.cacheEvents[1].reason == .noValidator)
  #expect(trace.cacheEvents.last?.reason == .replaced)
}

@Test func cacheMiddlewareSupportsCacheOnlyAndNetworkOnlyPolicies() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(data: Data("cached".utf8), statusCode: 200, headers: cacheControlHeaders("max-age=60"))
    ]
  )
  let transportState = CacheCountingTransportState()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: CacheCountingTransport(state: transportState)
  )
  let cacheOnlyRequest = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .cacheOnly)
  )
  let missingCacheOnlyRequest = TestRequest(
    path: "missing",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .cacheOnly)
  )
  let networkOnlyRequest = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .networkOnly)
  )

  let cached = try await client.send(cacheOnlyRequest)
  await #expect(throws: NetworkError.self) {
    _ = try await client.send(missingCacheOnlyRequest)
  }
  let network = try await client.send(networkOnlyRequest)
  let stored = try #require(await store.cachedResponse(for: key))

  #expect(cached == "cached")
  #expect(network == "network-1")
  #expect(await transportState.count() == 1)
  #expect(stored.data == Data("cached".utf8))
}

@Test func cacheOnlyDoesNotServeNoStoreOrNoCacheEntries() async throws {
  let noStoreKey = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/no-store")!)
  let noCacheKey = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/no-cache")!)
  var noStoreHeaders = HTTPFields()
  noStoreHeaders[HTTPField.Name("Cache-Control")!] = "no-store"
  var noCacheHeaders = HTTPFields()
  noCacheHeaders[HTTPField.Name("Cache-Control")!] = "no-cache"
  let store = MemoryHTTPCacheStore(
    responses: [
      noStoreKey: CachedHTTPResponse(
        data: Data("no-store".utf8),
        statusCode: 200,
        headers: noStoreHeaders
      ),
      noCacheKey: CachedHTTPResponse(
        data: Data("no-cache".utf8),
        statusCode: 200,
        headers: noCacheHeaders
      )
    ]
  )
  let transportState = CacheCountingTransportState()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: CacheCountingTransport(state: transportState)
  )

  await #expect(throws: NetworkError.self) {
    _ = try await client.send(
      TestRequest(
        path: "no-store",
        method: .get,
        responseSerializer: .string(),
        options: RequestOptions(cachePolicy: .cacheOnly)
      )
    )
  }
  await #expect(throws: NetworkError.self) {
    _ = try await client.send(
      TestRequest(
        path: "no-cache",
        method: .get,
        responseSerializer: .string(),
        options: RequestOptions(cachePolicy: .cacheOnly)
      )
    )
  }

  #expect(await transportState.count() == 0)
  #expect(await store.cachedResponse(for: noStoreKey) == nil)
  #expect(await store.cachedResponse(for: noCacheKey) != nil)
}

@Test func cacheMiddlewareDoesNotUseNoStoreEntryForStaleIfError() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  var cachedHeaders = HTTPFields()
  cachedHeaders[HTTPField.Name("Cache-Control")!] = "no-store"
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached".utf8),
        statusCode: 200,
        headers: cachedHeaders,
        storedAt: Date(timeIntervalSince1970: 0)
      )
    ]
  )
  let transportState = SequenceTransportState(results: [.failure(.timeout)])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        CacheMiddleware(
          store: store,
          now: { Date(timeIntervalSince1970: 10) }
        )
      ]
    ),
    transport: SequenceTransport(state: transportState)
  )
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(
      cachePolicy: HTTPCachePolicy(
        strategy: .returnCacheElseLoad,
        allowsStaleIfError: true
      )
    )
  )

  await #expect(throws: NetworkError.self) {
    _ = try await client.send(request)
  }

  #expect(await transportState.count() == 1)
  #expect(await store.cachedResponse(for: key) == nil)
}

@Test func cacheMiddlewareEvictsExistingEntryWhenResponseBecomesNoStore() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(data: Data("old".utf8), statusCode: 200)
    ]
  )
  var headers = HTTPFields()
  headers[HTTPField.Name("Cache-Control")!] = "no-store"
  let transport = SequenceTransport(
    state: SequenceTransportState(results: [
      .success(RawResponse(data: Data("new".utf8), statusCode: 200, headers: headers))
    ])
  )
  let client = HTTPClient.live(
    configuration: .init(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: transport
  )

  let response: String = try await client.send(
    TestRequest(
      path: "cache",
      method: .get,
      responseSerializer: .string(),
      options: RequestOptions(cachePolicy: .reloadIgnoringCache)
    )
  )

  #expect(response == "new")
  #expect(await store.cachedResponse(for: key) == nil)
}

@Test func cacheMiddlewareServesStaleResponseWhenNetworkFailsIfPolicyAllows() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  var cachedHeaders = HTTPFields()
  cachedHeaders[HTTPField.Name("Cache-Control")!] = "max-age=0"
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached".utf8),
        statusCode: 200,
        headers: cachedHeaders,
        storedAt: Date(timeIntervalSince1970: 0)
      )
    ]
  )
  let transportState = SequenceTransportState(results: [.failure(.timeout)])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        CacheMiddleware(
          store: store,
          now: { Date(timeIntervalSince1970: 10) }
        )
      ]
    ),
    transport: SequenceTransport(state: transportState)
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(
      cachePolicy: HTTPCachePolicy(
        strategy: .returnCacheElseLoad,
        allowsStaleIfError: true
      )
    )
  )

  let response = try await client.send(request)
  let trace = try #require(await traces.next())

  #expect(response == "cached")
  #expect(await transportState.count() == 1)
  #expect(trace.cacheEvents.map(\.kind) == [.stale, .revalidate, .hit])
  #expect(trace.cacheEvents[1].reason == .noValidator)
  #expect(trace.cacheEvents.last?.reason == .staleIfError)
}

@Test func cacheMiddlewareRespectsVaryHeaderValues() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/greeting")!)
  var englishHeaders = cacheControlHeaders("max-age=60")
  englishHeaders[HTTPField.Name("Vary")!] = "Accept-Language"
  var frenchHeaders = cacheControlHeaders("max-age=60")
  frenchHeaders[HTTPField.Name("Vary")!] = "Accept-Language"
  let transportState = ScriptedTransportState(
    responses: [
      RawResponse(data: Data("hello".utf8), statusCode: 200, headers: englishHeaders),
      RawResponse(data: Data("bonjour".utf8), statusCode: 200, headers: frenchHeaders)
    ]
  )
  let store = MemoryHTTPCacheStore()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: ScriptedTransport(state: transportState)
  )
  var englishRequestHeaders = HTTPFields()
  englishRequestHeaders[HTTPField.Name("Accept-Language")!] = "en"
  var frenchRequestHeaders = HTTPFields()
  frenchRequestHeaders[HTTPField.Name("Accept-Language")!] = "fr"
  let englishRequest = TestRequest(
    path: "greeting",
    method: .get,
    responseSerializer: .string(),
    headers: englishRequestHeaders,
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )
  let frenchRequest = TestRequest(
    path: "greeting",
    method: .get,
    responseSerializer: .string(),
    headers: frenchRequestHeaders,
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )

  let firstEnglish = try await client.send(englishRequest)
  let secondEnglish = try await client.send(englishRequest)
  let french = try await client.send(frenchRequest)
  let stored = try #require(await store.cachedResponse(for: key))

  #expect(firstEnglish == "hello")
  #expect(secondEnglish == "hello")
  #expect(french == "bonjour")
  #expect(await transportState.count() == 2)
  #expect(stored.requestVaryHeaderValues["accept-language"] == "fr")
}

@Test func cacheMiddlewareRejectsVaryWildcardResponses() async throws {
  var headers = cacheControlHeaders("max-age=60")
  headers[HTTPField.Name("Vary")!] = "*"
  let transportState = ScriptedTransportState(
    responses: [
      RawResponse(data: Data("first".utf8), statusCode: 200, headers: headers),
      RawResponse(data: Data("second".utf8), statusCode: 200, headers: headers)
    ]
  )
  let store = MemoryHTTPCacheStore()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: ScriptedTransport(state: transportState)
  )
  let request = TestRequest(
    path: "vary-star",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )

  let first = try await client.send(request)
  let second = try await client.send(request)

  #expect(first == "first")
  #expect(second == "second")
  #expect(await transportState.count() == 2)
  #expect(await store.count == 0)
}

@Test func cacheMiddlewareDoesNotServeMustRevalidateStaleResponseOnErrorWithoutDirective() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached".utf8),
        statusCode: 200,
        headers: cacheControlHeaders("max-age=0, must-revalidate"),
        storedAt: Date(timeIntervalSince1970: 0)
      )
    ]
  )
  let transportState = SequenceTransportState(results: [.failure(.timeout)])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store, now: { Date(timeIntervalSince1970: 10) })]
    ),
    transport: SequenceTransport(state: transportState)
  )
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(
      cachePolicy: HTTPCachePolicy(
        strategy: .returnCacheElseLoad,
        allowsStaleIfError: true
      )
    )
  )

  await #expect(throws: NetworkError.self) {
    _ = try await client.send(request)
  }

  #expect(await transportState.count() == 1)
}

@Test func cacheMiddlewareServesStaleWithinStaleIfErrorDirectiveWindow() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached".utf8),
        statusCode: 200,
        headers: cacheControlHeaders("max-age=0, must-revalidate, stale-if-error=30"),
        storedAt: Date(timeIntervalSince1970: 0)
      )
    ]
  )
  let transportState = SequenceTransportState(results: [.failure(.timeout)])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store, now: { Date(timeIntervalSince1970: 10) })]
    ),
    transport: SequenceTransport(state: transportState)
  )
  let request = TestRequest(
    path: "cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(
      cachePolicy: HTTPCachePolicy(
        strategy: .returnCacheElseLoad,
        allowsStaleIfError: true
      )
    )
  )

  let response = try await client.send(request)

  #expect(response == "cached")
  #expect(await transportState.count() == 1)
}

@Test func fileHTTPCacheStorePersistsResponsesAcrossInstances() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CometFileCacheTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let configuration = FileHTTPCacheStoreConfiguration(
    directoryURL: directory,
    namespace: "unit",
    maximumSizeBytes: 10_000
  )
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)
  var headers = HTTPFields()
  headers[.contentType] = "text/plain"
  let storedAt = Date(timeIntervalSince1970: 1_717_171_717)

  let writer = FileHTTPCacheStore(configuration: configuration)
  await writer.store(
    CachedHTTPResponse(
      data: Data("cached".utf8),
      statusCode: 200,
      headers: headers,
      storedAt: storedAt
    ),
    for: key
  )

  let reader = FileHTTPCacheStore(configuration: configuration)
  let cached = try #require(await reader.cachedResponse(for: key))

  #expect(cached.data == Data("cached".utf8))
  #expect(cached.statusCode == 200)
  #expect(cached.headers[.contentType] == "text/plain")
  #expect(cached.storedAt == storedAt)
  #expect(await reader.count() == 1)
}

@Test func fileHTTPCacheStorePrunesOldestEntriesWhenSizeLimitIsExceeded() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CometFileCacheTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let store = FileHTTPCacheStore(
    configuration: FileHTTPCacheStoreConfiguration(
      directoryURL: directory,
      namespace: "unit",
      maximumSizeBytes: 1_000
    )
  )
  let firstKey = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/first")!)
  let secondKey = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/second")!)

  await store.store(
    CachedHTTPResponse(
      data: Data(repeating: 1, count: 256),
      statusCode: 200,
      storedAt: Date(timeIntervalSince1970: 1)
    ),
    for: firstKey
  )
  await store.store(
    CachedHTTPResponse(
      data: Data(repeating: 2, count: 256),
      statusCode: 200,
      storedAt: Date(timeIntervalSince1970: 2)
    ),
    for: secondKey
  )

  #expect(await store.cachedResponse(for: firstKey) == nil)
  let cached = try #require(await store.cachedResponse(for: secondKey))
  #expect(cached.data == Data(repeating: 2, count: 256))
  #expect(await store.count() == 1)
  #expect(await store.currentSizeBytes() <= 1_000)
}

@Test func fileHTTPCacheStoreRemovesCorruptedEntriesWhenRead() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CometFileCacheTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let configuration = FileHTTPCacheStoreConfiguration(
    directoryURL: directory,
    namespace: "unit",
    maximumSizeBytes: 10_000
  )
  let store = FileHTTPCacheStore(configuration: configuration)
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)

  await store.store(CachedHTTPResponse(data: Data("cached".utf8), statusCode: 200), for: key)
  let files = try FileManager.default.contentsOfDirectory(
    at: configuration.resolvedDirectoryURL,
    includingPropertiesForKeys: nil
  )
  let file = try #require(files.first)
  try Data("not-json".utf8).write(to: file)

  #expect(await store.cachedResponse(for: key) == nil)
  #expect(await store.count() == 0)
}

@Test func fileHTTPCacheStoreRemovesMismatchedEntriesWhenRead() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CometFileCacheTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let configuration = FileHTTPCacheStoreConfiguration(
    directoryURL: directory,
    namespace: "unit",
    maximumSizeBytes: 10_000
  )
  let store = FileHTTPCacheStore(configuration: configuration)
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/cache")!)

  await store.store(CachedHTTPResponse(data: Data("cached".utf8), statusCode: 200), for: key)
  let files = try FileManager.default.contentsOfDirectory(
    at: configuration.resolvedDirectoryURL,
    includingPropertiesForKeys: nil
  )
  let file = try #require(files.first)
  let data = try Data(contentsOf: file)
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  object["url"] = "https://example.com/different"
  let tamperedData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  try tamperedData.write(to: file)

  #expect(await store.cachedResponse(for: key) == nil)
  #expect(await store.count() == 0)
}

@Test func fileHTTPCacheStoreSanitizesTraversalNamespaces() {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CometFileCacheTests-\(UUID().uuidString)", isDirectory: true)

  let dot = FileHTTPCacheStoreConfiguration(directoryURL: directory, namespace: ".")
  let dotDot = FileHTTPCacheStoreConfiguration(directoryURL: directory, namespace: "..")

  #expect(dot.resolvedDirectoryURL.lastPathComponent == "default")
  #expect(dotDot.resolvedDirectoryURL.lastPathComponent == "default")
  #expect(dot.resolvedDirectoryURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
  #expect(dotDot.resolvedDirectoryURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
}

@Test func httpClientStreamsResponseLines() async throws {
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: StaticStreamingTransport(
      response: RawResponse(data: Data("one\ntwo\r\nthree".utf8), statusCode: 200)
    )
  )
  let request = TestRequest(
    path: "lines",
    method: .get,
    responseSerializer: .string()
  )
  var lines: [String] = []

  for try await line in client.lines(request, chunkSize: 3) {
    lines.append(line)
  }

  #expect(lines == ["one", "two", "three"])
}

@Test func httpClientStreamsCachedMiddlewareResponsesWithoutLiveStream() async throws {
  let key = HTTPCacheKey(method: .get, url: URL(string: "https://example.com/stream-cache")!)
  let store = MemoryHTTPCacheStore(
    responses: [
      key: CachedHTTPResponse(
        data: Data("cached-stream".utf8),
        statusCode: 200,
        headers: cacheControlHeaders("max-age=60")
      )
    ]
  )
  let transportState = CountingStreamingTransportState()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [CacheMiddleware(store: store)]
    ),
    transport: CountingStreamingTransport(
      state: transportState,
      response: RawResponse(data: Data("network-stream".utf8), statusCode: 200)
    )
  )
  var traces = client.traces.makeAsyncIterator()
  let request = TestRequest(
    path: "stream-cache",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(cachePolicy: .returnCacheElseLoad)
  )
  var body = Data()
  var statusCode: Int?

  for try await event in client.stream(request, chunkSize: 2) {
    switch event {
    case .response(let response):
      statusCode = response.statusCode
    case .bytes(let data):
      body.append(data)
    case .complete:
      break
    }
  }
  let trace = try #require(await traces.next())

  #expect(statusCode == 200)
  #expect(String(data: body, encoding: .utf8) == "cached-stream")
  #expect(await transportState.count() == 0)
  #expect(trace.cacheEvents.map(\.kind) == [.hit])
}

@Test func httpClientParsesServerSentEvents() async throws {
  let body = """
  id: 1
  event: message
  data: hello
  data: world
  retry: 1500

  : ignored comment
  data: done

  """
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: StaticStreamingTransport(
      response: RawResponse(data: Data(body.utf8), statusCode: 200)
    )
  )
  let request = TestRequest(
    path: "events",
    method: .get,
    responseSerializer: .string()
  )
  var events: [ServerSentEvent] = []

  for try await event in client.serverSentEvents(request, chunkSize: 5) {
    events.append(event)
  }

  #expect(events == [
    ServerSentEvent(event: "message", id: "1", data: "hello\nworld", retryMilliseconds: 1_500),
    ServerSentEvent(data: "done")
  ])
}

@Test func httpClientReportsTransferProgress() async throws {
  let recorder = ProgressRecorder()
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: StaticStreamingTransport(
      response: RawResponse(data: Data("ok".utf8), statusCode: 200)
    )
  )
  let request = TestRequest(
    path: "upload",
    method: .post,
    responseSerializer: .data,
    body: .text("upload")
  )

  let response = try await client.sendRaw(request) { progress in
    await recorder.record(progress)
  }

  #expect(response.data == Data("ok".utf8))
  #expect(await recorder.snapshot() == [
    TransferProgress(kind: .upload, completedBytes: 6, totalBytes: 6),
    TransferProgress(kind: .download, completedBytes: 2, totalBytes: 2)
  ])
}

@Test func networkEventExposesDiagnosticProperties() {
  let id = UUID()
  let url = URL(string: "https://example.com/todos/1")!
  let metadata = RequestMetadata(name: "GetTodo", tags: ["todos"], operationID: "getTodo")
  let started = NetworkEvent.requestStarted(id: id, method: .get, url: url, metadata: metadata)
  let completed = NetworkEvent.requestCompleted(id: id, statusCode: 200, duration: .milliseconds(12), metadata: metadata)
  let failed = NetworkEvent.requestFailed(id: id, error: .timeout, duration: .seconds(1), metadata: metadata)
  let retried = NetworkEvent.requestRetried(id: id, attempt: 2, delay: .milliseconds(250), metadata: metadata)

  #expect(started.kind == .started)
  #expect(started.id == id)
  #expect(started.method == .get)
  #expect(started.url == url)
  #expect(started.metadata == metadata)
  #expect(started.displayName == "GetTodo")
  #expect(started.diagnosticSummary.contains("started GetTodo GET https://example.com/todos/1"))

  #expect(completed.kind == .completed)
  #expect(completed.statusCode == 200)
  #expect(completed.duration == .milliseconds(12))
  #expect(completed.error == nil)
  #expect(completed.diagnosticSummary.contains("HTTP 200"))

  #expect(failed.kind == .failed)
  #expect(failed.error?.isTimeoutError == true)
  #expect(failed.duration == .seconds(1))
  #expect(failed.diagnosticSummary.contains("timed out"))

  #expect(retried.kind == .retried)
  #expect(retried.retryAttempt == 2)
  #expect(retried.retryDelay == .milliseconds(250))
  #expect(retried.statusCode == nil)
  #expect(retried.diagnosticSummary.contains("attempt 2"))
}

@Test func retryMiddlewareDoesNotRetryUnsafeWritesWithoutOptIn() async {
  let transportState = SequenceTransportState(results: [
    .failure(.timeout),
    .success(RawResponse(data: Data("ok".utf8), statusCode: 200))
  ])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [RetryMiddleware(maxAttempts: 2)],
      sleep: { _ in }
    ),
    transport: SequenceTransport(state: transportState)
  )
  let request = TestRequest(
    path: "write",
    method: .post,
    responseSerializer: .string(),
    body: .text("unsafe")
  )

  await #expect(throws: NetworkError.self) {
    _ = try await client.send(request)
  }
  #expect(await transportState.count() == 1)
}

@Test func authenticationMiddlewareRefreshesAndReplaysAuthorizedSafeRequest() async throws {
  let authStore = AuthTestStore(token: "old", refreshToken: "new")
  let coordinator = AuthenticationCoordinator.bearer(
    token: { await authStore.token() },
    refresh: { await authStore.refresh() }
  )
  let transportState = AuthTransportState(responses: [
    RawResponse(data: Data("unauthorized".utf8), statusCode: 401),
    RawResponse(data: Data("ok".utf8), statusCode: 200)
  ])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [AuthenticationMiddleware(coordinator: coordinator)]
    ),
    transport: AuthTransport(state: transportState)
  )
  let request = TestRequest(
    path: "secure",
    method: .get,
    responseSerializer: .string()
  )

  let response = try await client.send(request)

  #expect(response == "ok")
  #expect(await authStore.refreshCount() == 1)
  #expect(await transportState.authorizations() == ["Bearer old", "Bearer new"])
}

@Test func authenticationCoordinatorDeduplicatesConcurrentRefreshes() async throws {
  let authStore = AuthTestStore(
    token: "old",
    refreshToken: "new",
    refreshDelay: .milliseconds(20)
  )
  let coordinator = AuthenticationCoordinator.bearer(
    token: { await authStore.token() },
    refresh: { await authStore.refresh() }
  )

  async let first = coordinator.refreshCredential()
  async let second = coordinator.refreshCredential()
  let credentials = try await [first, second]

  #expect(credentials.map { $0?.headerValue } == ["Bearer new", "Bearer new"])
  #expect(await authStore.refreshCount() == 1)
}

@Test func authenticationMiddlewareDoesNotReplayUnsafeWriteWithoutRetryOptIn() async {
  let authStore = AuthTestStore(token: "old", refreshToken: "new")
  let coordinator = AuthenticationCoordinator.bearer(
    token: { await authStore.token() },
    refresh: { await authStore.refresh() }
  )
  let transportState = AuthTransportState(responses: [
    RawResponse(data: Data("unauthorized".utf8), statusCode: 401)
  ])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [AuthenticationMiddleware(coordinator: coordinator)]
    ),
    transport: AuthTransport(state: transportState)
  )
  let request = TestRequest(
    path: "secure",
    method: .post,
    responseSerializer: .string()
  )

  do {
    _ = try await client.send(request)
    Issue.record("Expected the unsafe write to preserve the 401 response without auth replay.")
  } catch let error {
    #expect(error.statusCode == 401)
  }

  #expect(await authStore.refreshCount() == 0)
  #expect(await transportState.authorizations() == ["Bearer old"])
}

@Test func retryMiddlewareRetriesWritesWithIdempotencyKey() async throws {
  let transportState = SequenceTransportState(results: [
    .failure(.timeout),
    .success(RawResponse(data: Data("ok".utf8), statusCode: 200))
  ])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [RetryMiddleware(maxAttempts: 2)],
      sleep: { _ in }
    ),
    transport: SequenceTransport(state: transportState)
  )
  let request = TestRequest(
    path: "write",
    method: .post,
    responseSerializer: .string(),
    body: .text("safe"),
    options: RequestOptions(idempotencyKey: "write-1")
  )

  let response = try await client.send(request)

  #expect(response == "ok")
  #expect(await transportState.count() == 2)
}

@Test func retryMiddlewareHonorsExplicitRequestRetryPolicy() async throws {
  let transportState = SequenceTransportState(results: [
    .failure(.timeout),
    .success(RawResponse(data: Data("ok".utf8), statusCode: 200))
  ])
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [RetryMiddleware(maxAttempts: 2)],
      sleep: { _ in }
    ),
    transport: SequenceTransport(state: transportState)
  )
  let request = TestRequest(
    path: "write",
    method: .post,
    responseSerializer: .string(),
    body: .text("explicit"),
    options: RequestOptions(retryPolicy: .always)
  )

  let response = try await client.send(request)

  #expect(response == "ok")
  #expect(await transportState.count() == 2)
}

@Test func deduplicationCoalescesConcurrentCallers() async throws {
  let transport = WaitingTransport()
  let client = HTTPClient.live(
    configuration: .default(baseURL: URL(string: "https://example.com")!),
    transport: transport
  )

  let request = TestRequest(
    path: "slow",
    method: .get,
    responseSerializer: .string(),
    options: RequestOptions(deduplicationKey: "shared")
  )

  let first = Task {
    try await client.send(request)
  }

  while await transport.count() != 1 {
    await Task.yield()
  }

  let second = Task {
    try await client.send(request)
  }

  for _ in 0..<20 {
    if await transport.count() == 1 {
      break
    }
    await Task.yield()
  }

  #expect(await transport.count() == 1)

  await transport.resolveAll(with: .success(RawResponse(data: Data("done".utf8), statusCode: 200)))
  let firstResponse = try await first.value
  let secondResponse = try await second.value

  #expect(firstResponse == "done")
  #expect(secondResponse == "done")
  #expect(await transport.count() == 1)
}

@Test func loggingMiddlewareHonorsConfiguredLevel() async throws {
  let requestSink = LogSink()
  let requestClient = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        LoggingMiddleware(logLevel: .request) { message in
          requestSink.append(message)
        }
      ]
    ),
    transport: TestTransport { _ in
      RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )

  let responseSink = LogSink()
  let responseClient = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        LoggingMiddleware(logLevel: .response) { message in
          responseSink.append(message)
        }
      ]
    ),
    transport: TestTransport { _ in
      RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )

  let verboseSink = LogSink()
  let verboseClient = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        LoggingMiddleware(logLevel: .verbose) { message in
          verboseSink.append(message)
        }
      ]
    ),
    transport: TestTransport { _ in
      RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )

  let request = TestRequest(
    path: "logs",
    method: .post,
    responseSerializer: .string(),
    body: .text("hello"),
    options: RequestOptions(metadata: RequestMetadata(name: "LogProof"))
  )

  _ = try await requestClient.send(request)
  _ = try await responseClient.send(request)
  _ = try await verboseClient.send(request)

  let requestLogs = requestSink.snapshot()
  let responseLogs = responseSink.snapshot()
  let verboseLogs = verboseSink.snapshot()

  #expect(requestLogs.count == 1)
  #expect(requestLogs[0].contains("→"))
  #expect(requestLogs[0].contains("LogProof"))
  #expect(!requestLogs[0].contains("←"))

  #expect(responseLogs.count == 1)
  #expect(responseLogs[0].contains("← 200"))

  #expect(verboseLogs.count == 3)
  #expect(verboseLogs.contains(where: { $0.contains("→") }))
  #expect(verboseLogs.contains(where: { $0.contains("curl") }))
  #expect(verboseLogs.contains(where: { $0.contains("← 200") }))
}

@Test func loggingMiddlewareCanEmitCompactCurlCommands() async throws {
  let verboseSink = LogSink()
  let client = HTTPClient.live(
    configuration: ClientConfiguration(
      baseURL: URL(string: "https://example.com")!,
      middleware: [
        LoggingMiddleware(
          logLevel: .verbose,
          curlCommandOptions: CURLCommandOptions(style: .compact)
        ) { message in
          verboseSink.append(message)
        }
      ]
    ),
    transport: TestTransport { _ in
      RawResponse(data: Data("ok".utf8), statusCode: 200)
    }
  )
  let request = TestRequest(
    path: "logs",
    method: .post,
    responseSerializer: .string(),
    body: .json(["message": "hello"])
  )

  _ = try await client.send(request)

  let curlLog = verboseSink.snapshot().first { $0.hasPrefix("curl") }
  #expect(curlLog?.contains("\\\n") == false)
  #expect(curlLog?.contains("--data-raw") == true)
}

@Test func curlCommandIsShellSafeAndUsesRedactionPolicy() {
  var headers = HTTPFields()
  headers[.authorization] = "Bearer secret"
  headers[HTTPField.Name("X-Name")!] = "O'Reilly"

  let prepared = PreparedRequest(
    url: URL(string: "https://example.com/search?q=hello%20world")!,
    method: .post,
    headers: headers,
    body: Data("hello 'world'".utf8),
    timeout: .seconds(5),
    redactionPolicy: RedactionPolicy(
      redactedHeaders: ["authorization"],
      redactRequestBody: { _ in true }
    )
  )

  let curl = prepared.curlCommand()

  #expect(curl.contains("-X 'POST'"))
  #expect(curl.contains("-H 'authorization: <redacted>'"))
  #expect(curl.contains("-H 'x-name: O'\\''Reilly'"))
  #expect(curl.contains("--data-raw '<redacted>'"))
  #expect(curl.contains("'https://example.com/search?q=hello%20world'"))

  let compact = prepared.curlCommand(style: .compact)
  #expect(!compact.contains("\\\n"))
  #expect(compact.contains("curl -X 'POST' -H 'authorization: <redacted>'"))
}

@Test func curlCommandCanPrettyPrintJSONBodies() {
  var headers = HTTPFields()
  headers[.contentType] = "application/json"
  let prepared = PreparedRequest(
    url: URL(string: "https://example.com/search")!,
    method: .post,
    headers: headers,
    body: Data(#"{"z":1,"a":{"b":2}}"#.utf8),
    timeout: .seconds(5)
  )

  let curl = prepared.curlCommand(
    options: CURLCommandOptions(
      style: .multiline,
      bodyFormatting: .prettyPrintedJSON
    )
  )

  #expect(curl.contains("--data-raw '{\n"))
  #expect(curl.contains(#""a" : {"#))
  #expect(curl.contains(#""z" : 1"#))
}

@Test func textBodyThrowsWhenEncodingFails() {
  let body = HTTPBody.text("Comet🙂", encoding: .ascii)

  #expect(throws: NetworkError.self) {
    _ = try body.resolved(using: .default(baseURL: URL(string: "https://example.com")!))
  }
}

@Test func jsonPresetHelpersExposeStandardAndSnakeCaseBehaviors() throws {
  struct Payload: Codable, Sendable {
    let userId: Int
  }

  let standardData = try ClientConfiguration.defaultJSONEncoder().encode(Payload(userId: 1))
  let snakeCaseData = try ClientConfiguration.snakeCaseJSONEncoder().encode(Payload(userId: 1))

  #expect(String(decoding: standardData, as: UTF8.self).contains("userId"))
  #expect(String(decoding: snakeCaseData, as: UTF8.self).contains("user_id"))
}

@Test func networkErrorExposesReadableHTTPMetadata() throws {
  let body = Data(#"{"message":"not found","code":404}"#.utf8)
  var headers = HTTPFields()
  headers[.contentType] = "application/json; charset=utf-8"
  let error = NetworkError.http(statusCode: 404, body: body, headers: headers)

  #expect(error.statusCode == 404)
  #expect(error.bodyString == #"{"message":"not found","code":404}"#)
  #expect(error.prettyBodyJSONString?.contains(#""message" : "not found""#) == true)
  #expect(error.debugSummary.contains("HTTP 404"))
}

@Test func networkErrorFlagsConnectivityAndTimeoutCases() {
  let transportError = NetworkError.transport(URLError(.notConnectedToInternet))
  let timeoutError = NetworkError.timeout

  #expect(transportError.isConnectivityError)
  #expect(!transportError.isTimeoutError)
  #expect(timeoutError.isTimeoutError)
  #expect(!timeoutError.isConnectivityError)
}

@Test func preparedRequestBuildsURLRequest() {
  var headers = HTTPFields()
  headers[.contentType] = "application/json"

  let prepared = PreparedRequest(
    url: URL(string: "https://example.com/todos/1")!,
    method: .post,
    headers: headers,
    body: Data("{}".utf8),
    timeout: .seconds(5)
  )

  let request = prepared.urlRequest

  #expect(request.url?.absoluteString == "https://example.com/todos/1")
  #expect(request.httpMethod == "POST")
  #expect(request.httpBody == Data("{}".utf8))
  #expect(request.timeoutInterval == 5)
  #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
}

@Test func eventBroadcasterUsesBoundedNewestBuffering() async {
  let broadcaster = EventBroadcaster<Int>(bufferingPolicy: .bufferingNewest(2))
  let stream = broadcaster.stream()
  var iterator = stream.makeAsyncIterator()

  broadcaster.emit(1)
  broadcaster.emit(2)
  broadcaster.emit(3)
  broadcaster.finish()

  let first = await iterator.next()
  let second = await iterator.next()
  let third = await iterator.next()

  #expect(first == 2)
  #expect(second == 3)
  #expect(third == nil)
}

@Test func activityBufferingPolicyClampsNegativeLimits() async {
  let newestBroadcaster = EventBroadcaster<Int>(
    bufferingPolicy: NetworkActivityBufferingPolicy.bufferingNewest(-5).asyncStreamPolicy(for: Int.self)
  )
  let oldestBroadcaster = EventBroadcaster<Int>(
    bufferingPolicy: NetworkActivityBufferingPolicy.bufferingOldest(-5).asyncStreamPolicy(for: Int.self)
  )
  var newest = newestBroadcaster.stream().makeAsyncIterator()
  var oldest = oldestBroadcaster.stream().makeAsyncIterator()

  newestBroadcaster.emit(1)
  oldestBroadcaster.emit(1)
  newestBroadcaster.finish()
  oldestBroadcaster.finish()

  #expect(await newest.next() == nil)
  #expect(await oldest.next() == nil)
}

@Test func staticReachabilityHintProviderReturnsConfiguredSnapshot() async {
  let checkedAt = Date(timeIntervalSince1970: 123)
  let provider = StaticReachabilityHintProvider(
    ReachabilitySnapshot(
      status: .reachable,
      isExpensive: true,
      isConstrained: false,
      checkedAt: checkedAt
    )
  )

  let snapshot = await provider.currentSnapshot()

  #expect(snapshot.status == .reachable)
  #expect(snapshot.isExpensive == true)
  #expect(snapshot.isConstrained == false)
  #expect(snapshot.checkedAt == checkedAt)
}
