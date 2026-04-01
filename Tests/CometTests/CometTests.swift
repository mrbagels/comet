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
    responseSerializer: .string()
  )

  let response = try await client.send(request)
  let events = await [iterator.next(), iterator.next(), iterator.next()].compactMap { $0 }

  #expect(response == "ok")
  #expect(await transportState.count() == 2)
  #expect(await sleepRecorder.snapshot().map(durationMilliseconds) == [1_500])
  #expect(events.count == 3)

  guard case .requestStarted = events[0] else {
    Issue.record("Expected requestStarted as the first activity event.")
    return
  }

  guard case .requestRetried(_, let attempt, let delay) = events[1] else {
    Issue.record("Expected requestRetried as the second activity event.")
    return
  }
  #expect(attempt == 1)
  #expect(durationMilliseconds(delay) == 1_500)

  guard case .requestCompleted(_, let statusCode, _) = events[2] else {
    Issue.record("Expected requestCompleted as the third activity event.")
    return
  }
  #expect(statusCode == 200)
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
    body: .text("hello")
  )

  _ = try await requestClient.send(request)
  _ = try await responseClient.send(request)
  _ = try await verboseClient.send(request)

  let requestLogs = requestSink.snapshot()
  let responseLogs = responseSink.snapshot()
  let verboseLogs = verboseSink.snapshot()

  #expect(requestLogs.count == 1)
  #expect(requestLogs[0].contains("→"))
  #expect(!requestLogs[0].contains("←"))

  #expect(responseLogs.count == 1)
  #expect(responseLogs[0].contains("← 200"))

  #expect(verboseLogs.count == 3)
  #expect(verboseLogs.contains(where: { $0.contains("→") }))
  #expect(verboseLogs.contains(where: { $0.contains("curl") }))
  #expect(verboseLogs.contains(where: { $0.contains("← 200") }))
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
