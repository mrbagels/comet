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

private func durationMilliseconds(_ duration: Duration) -> Int64 {
  let components = duration.components
  return components.seconds * 1_000
    + Int64(Double(components.attoseconds) / 1_000_000_000_000_000)
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
