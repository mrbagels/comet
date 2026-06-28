import Foundation
import HTTPTypes
import Observation
import Comet
import CometTesting

@MainActor
@Observable
final class DemoCatalog {
  enum DemoCategory: String, CaseIterable, Identifiable {
    case requests
    case transport
    case failures
    case realtime

    var id: String { self.rawValue }

    var title: String {
      switch self {
      case .requests: "Requests"
      case .transport: "Transport"
      case .failures: "Failures"
      case .realtime: "Realtime"
      }
    }

    var subtitle: String {
      switch self {
      case .requests:
        "Typed serialization, URL shaping, and content transforms."
      case .transport:
        "Status validation, raw inspection, and payload-free flows."
      case .failures:
        "Timeouts, authorization failures, retries, decoding errors, cancellation, and socket closure."
      case .realtime:
        "Bidirectional sessions, echo transcripts, and socket transport swaps."
      }
    }

    var symbolName: String {
      switch self {
      case .requests: "point.3.connected.trianglepath.dotted"
      case .transport: "waveform.path.ecg.rectangle"
      case .failures: "exclamationmark.triangle"
      case .realtime: "dot.radiowaves.left.and.right"
      }
    }

    var demos: [Demo] {
      Demo.allCases.filter { $0.category == self }
    }
  }

  enum Demo: String, CaseIterable, Identifiable {
    case json
    case text
    case empty
    case raw
    case timeout
    case unauthorized
    case rateLimited
    case serverError
    case malformedJSON
    case cancelled
    case webSocket
    case webSocketClose

    var id: String { self.rawValue }

    var title: String {
      switch self {
      case .json: "Typed JSON"
      case .text: "Plain Text"
      case .empty: "Empty Response"
      case .raw: "Raw Response"
      case .timeout: "Timeout"
      case .unauthorized: "Typed 401"
      case .rateLimited: "429 Retry"
      case .serverError: "Server Error"
      case .malformedJSON: "Malformed JSON"
      case .cancelled: "Cancellation"
      case .webSocket: "WebSocket Echo"
      case .webSocketClose: "Socket Close"
      }
    }

    var subtitle: String {
      switch self {
      case .json:
        "Decode a strongly typed model with `APIRequest`, `Path`, and `ResponseSerializer.json`."
      case .text:
        "Read a plain text payload with `RequestOptions.absoluteURL` and `ResponseSerializer.string`."
      case .empty:
        "Validate a 204-style endpoint using `EmptyResponse`."
      case .raw:
        "Inspect bytes, headers, and status directly with `sendRaw`."
      case .timeout:
        "Verify timeout errors flow through `NetworkError` and activity events."
      case .unauthorized:
        "Decode a structured 401 response with `APIRequestWithErrorResponse`."
      case .rateLimited:
        "Exercise retry middleware with an initial 429 and a recovered response."
      case .serverError:
        "Confirm non-success status validation preserves HTTP status and body details."
      case .malformedJSON:
        "Trigger response decoding failure while preserving useful diagnostics."
      case .cancelled:
        "Verify cancellation is represented as a first-class networking error."
      case .webSocket:
        "Open a socket, send JSON, and inspect the echoed transcript with the WebSocket client surface."
      case .webSocketClose:
        "Close a socket and verify the close frame is surfaced through `NetworkError`."
      }
    }

    var category: DemoCategory {
      switch self {
      case .json, .text:
        .requests
      case .empty, .raw:
        .transport
      case .timeout, .unauthorized, .rateLimited, .serverError, .malformedJSON, .cancelled:
        .failures
      case .webSocket:
        .realtime
      case .webSocketClose:
        .realtime
      }
    }

    var symbolName: String {
      switch self {
      case .json: "sparkles.rectangle.stack"
      case .text: "text.page"
      case .empty: "checkmark.circle.badge.xmark"
      case .raw: "bolt.horizontal.circle"
      case .timeout: "timer"
      case .unauthorized: "lock.trianglebadge.exclamationmark"
      case .rateLimited: "arrow.clockwise.circle"
      case .serverError: "server.rack"
      case .malformedJSON: "curlybraces.square"
      case .cancelled: "xmark.circle"
      case .webSocket: "dot.radiowaves.up.forward"
      case .webSocketClose: "rectangle.connected.to.line.below"
      }
    }

    var packageSurface: [String] {
      switch self {
      case .json:
        ["HTTPClient.send", "APIRequest", "Path", "ResponseSerializer.json"]
      case .text:
        ["HTTPClient.send", "RequestOptions.absoluteURL", "ResponseSerializer.string"]
      case .empty:
        ["HTTPClient.send", "EmptyResponse", "StatusValidation"]
      case .raw:
        ["HTTPClient.sendRaw", "RawResponse", "HTTPFields"]
      case .timeout:
        ["HTTPClient.send", "NetworkError.timeout", "RequestOptions.timeout"]
      case .unauthorized:
        ["HTTPClient.sendWithTypedErrors", "APIClientError", "ErrorResponseSerializer.json"]
      case .rateLimited:
        ["RetryMiddleware", "RequestRetryPolicy", "NetworkEvent.requestRetried"]
      case .serverError:
        ["StatusValidation", "NetworkError.http", "NetworkError.bodyString"]
      case .malformedJSON:
        ["ResponseSerializer.json", "NetworkError.decoding", "ClientConfiguration.makeJSONDecoder"]
      case .cancelled:
        ["HTTPClient.send", "NetworkError.cancelled", "NetworkError.isCancellationError"]
      case .webSocket:
        [
          "WebSocketClient.connect",
          "WebSocketRequest",
          "URLSessionWebSocketTransport",
          "MockWebSocketTransport"
        ]
      case .webSocketClose:
        ["WebSocketConnection.close", "NetworkError.webSocketClosed", "WebSocketCloseCode"]
      }
    }

    func verificationChecklist(for mode: ClientMode) -> [String] {
      switch (self, mode) {
      case (.json, .mock):
        [
          "Output contains `Mock transport says hello`.",
          "The decoded fields show a typed todo model."
        ]
      case (.json, .live):
        [
          "Output contains a title from JSONPlaceholder.",
          "The activity feed shows a real HTTPS request."
        ]
      case (.text, .mock):
        [
          "Output equals `Comet mock text response`.",
          "The request proves `absoluteURL` bypasses the base URL cleanly."
        ]
      case (.text, .live):
        [
          "Output includes the Example Domain page text.",
          "The activity feed records a `https://example.com` request."
        ]
      case (.empty, .mock):
        [
          "The result confirms `EmptyResponse` succeeded.",
          "No payload decoding is required for the check to pass."
        ]
      case (.empty, .live):
        [
          "The result confirms a live 204-style response succeeded.",
          "The activity feed records a completion event."
        ]
      case (.raw, .mock):
        [
          "Status is `200` and `content-type` is `application/json`.",
          "The payload text still contains the mock todo title."
        ]
      case (.raw, .live):
        [
          "Status is `200` and the body bytes are non-empty.",
          "The raw payload is visible without decoding first."
        ]
      case (.timeout, .mock):
        [
          "The result records `NetworkError.timeout` as an expected failure.",
          "The activity feed shows a failed timeout event."
        ]
      case (.timeout, .live):
        [
          "The request uses a short timeout against a delayed endpoint.",
          "The result records a timeout-shaped failure."
        ]
      case (.unauthorized, .mock):
        [
          "The 401 body decodes into `DemoAPIError`.",
          "The raw HTTP status remains available through `APIClientError`."
        ]
      case (.unauthorized, .live):
        [
          "The 401 status is preserved even if the live endpoint has no typed JSON body.",
          "The result distinguishes HTTP failure from transport failure."
        ]
      case (.rateLimited, .mock):
        [
          "The first response is `429` and retry middleware performs one retry.",
          "The final output confirms recovery after the retry."
        ]
      case (.rateLimited, .live):
        [
          "The live 429 endpoint exercises retry middleware.",
          "The final output preserves the 429 status after retries are exhausted."
        ]
      case (.serverError, .mock):
        [
          "The result preserves the mock `500` status code.",
          "The output includes the server error body text."
        ]
      case (.serverError, .live):
        [
          "The result preserves the live `500` status code.",
          "The activity feed records a failed request."
        ]
      case (.malformedJSON, .mock):
        [
          "The HTTP response succeeds but JSON decoding fails.",
          "The output identifies a `NetworkError.decoding` result."
        ]
      case (.malformedJSON, .live):
        [
          "The live response is intentionally not shaped like `DemoTodo`.",
          "The output identifies a decoding result."
        ]
      case (.cancelled, .mock):
        [
          "The mock transport throws `NetworkError.cancelled`.",
          "The output confirms cancellation is detected explicitly."
        ]
      case (.cancelled, .live):
        [
          "The demo uses Comet's failing client to produce deterministic cancellation.",
          "The output confirms cancellation is detected explicitly."
        ]
      case (.webSocket, .mock):
        [
          "The transcript shows a mocked socket URL and negotiated subprotocol.",
          "The echoed payload matches the JSON message sent over the connection."
        ]
      case (.webSocket, .live):
        [
          "The transcript shows a live `wss://` endpoint and echoed payload.",
          "The connection closes cleanly after the response is received."
        ]
      case (.webSocketClose, .mock):
        [
          "The mock session closes with code `1001`.",
          "A receive after close reports `NetworkError.webSocketClosed`."
        ]
      case (.webSocketClose, .live):
        [
          "The connection is closed intentionally before the next receive.",
          "The output reports the close code surfaced by the transport."
        ]
      }
    }

    var traceMetadataName: String? {
      switch self {
      case .json:
        "TodoDemo"
      case .text:
        "TextDemo"
      case .empty:
        "EmptyDemo"
      case .raw:
        "RawTodoDemo"
      case .timeout:
        "TimeoutDemo"
      case .unauthorized:
        "UnauthorizedDemo"
      case .rateLimited:
        "RateLimitDemo"
      case .serverError:
        "ServerErrorDemo"
      case .malformedJSON:
        "MalformedJSONDemo"
      case .cancelled:
        "CancelledDemo"
      case .webSocket, .webSocketClose:
        nil
      }
    }
  }

  enum ClientMode: String, CaseIterable, Identifiable {
    case mock
    case live

    var id: String { self.rawValue }

    var title: String {
      switch self {
      case .mock: "Mock"
      case .live: "Live"
      }
    }

    var blurb: String {
      switch self {
      case .mock:
        "Deterministic HTTP and socket flows from `MockTransport` and `MockWebSocketTransport`."
      case .live:
        "Real HTTP and WebSocket traffic through URLSession-backed transports."
      }
    }
  }

  struct DemoState: Sendable {
    enum Status: String, Sendable {
      case idle
      case running
      case passed
      case failed
    }

    var output: String
    var status: Status
    var detail: String
    var response: DemoResponseSnapshot? = nil
    var socket: DemoSocketMonitorSnapshot? = nil
    var cassette: DemoCassetteSnapshot? = nil
  }

  var mode: ClientMode = .mock {
    didSet {
      guard oldValue != mode else { return }
      self.configureClient()
    }
  }

  private(set) var demoStates: [Demo: DemoState]
  var activityLog: [DemoActivityEntry] = []
  var runSummary = "Start in Mock mode and run the proof set to verify Comet end-to-end."

  private var client: HTTPClient
  private var socketClient: WebSocketClient
  private let activityObserver = ActivityObserver()

  init() {
    self.demoStates = Self.makeInitialStates()
    self.client = DemoClientFactory.makeClient(mode: .mock)
    self.socketClient = DemoClientFactory.makeWebSocketClient(mode: .mock)
    self.subscribeToActivity()
  }

  var completedChecks: Int {
    self.demoStates.values.filter { $0.status == .passed }.count
  }

  var failedChecks: Int {
    self.demoStates.values.filter { $0.status == .failed }.count
  }

  var inFlightChecks: Int {
    self.demoStates.values.filter { $0.status == .running }.count
  }

  func state(for demo: Demo) -> DemoState {
    self.demoStates[demo, default: Self.placeholderState(for: demo)]
  }

  func requestInspection(for demo: Demo) -> DemoRequestInspection {
    switch demo {
    case .json:
      return self.httpInspection(for: TodoRequest(), demo: demo)
    case .text:
      return self.httpInspection(for: TextDemoRequest(), demo: demo)
    case .empty:
      return self.httpInspection(for: EmptyDemoRequest(), demo: demo)
    case .raw:
      return self.httpInspection(for: RawTodoRequest(), demo: demo)
    case .timeout:
      return self.httpInspection(for: TimeoutDemoRequest(mode: self.mode), demo: demo)
    case .unauthorized:
      return self.httpInspection(
        for: UnauthorizedDemoRequest(mode: self.mode),
        demo: demo,
        extraFields: [
          DemoInspectorField(label: "Typed error", value: String(describing: DemoAPIError.self))
        ]
      )
    case .rateLimited:
      return self.httpInspection(for: RateLimitDemoRequest(mode: self.mode), demo: demo)
    case .serverError:
      return self.httpInspection(for: ServerErrorDemoRequest(mode: self.mode), demo: demo)
    case .malformedJSON:
      return self.httpInspection(for: MalformedJSONDemoRequest(mode: self.mode), demo: demo)
    case .cancelled:
      let inspectionClient = self.mode == .mock
        ? self.client
        : HTTPClient.failing(with: .cancelled)
      return self.httpInspection(
        for: CancelledDemoRequest(),
        demo: demo,
        client: inspectionClient,
        transport: self.mode == .mock ? self.mode.httpTransportName : "FailingTransport"
      )
    case .webSocket:
      return self.webSocketInspection(
        for: DemoClientFactory.makeWebSocketRequest(mode: self.mode),
        demo: demo,
        transport: self.mode.webSocketTransportName
      )
    case .webSocketClose:
      return self.webSocketInspection(
        for: Self.socketCloseRequest(),
        demo: demo,
        transport: "MockWebSocketTransport"
      )
    }
  }

  func traceTimeline(for demo: Demo) -> DemoTraceTimeline? {
    Self.traceTimeline(
      for: demo,
      mode: self.mode,
      entries: Self.traceEntries(for: demo, activityLog: self.activityLog)
    )
  }

  func run(_ demo: Demo) async {
    self.demoStates[demo]?.status = .running
    self.demoStates[demo]?.detail = "Request in flight..."

    do {
      switch demo {
      case .json:
        let todo = try await self.client.send(TodoRequest())
        let output = Self.prettyPrintedJSON(for: todo)
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Decoded a typed `DemoTodo` and rendered formatted JSON.",
          response: Self.responseSnapshot(
            title: "Decoded JSON response",
            summary: "A `DemoTodo` value decoded through `ResponseSerializer.json`.",
            fields: [
              DemoInspectorField(label: "Format", value: "JSON"),
              DemoInspectorField(label: "Model", value: String(describing: DemoTodo.self)),
              DemoInspectorField(label: "Expected status", value: "200")
            ],
            body: output
          )
        )
      case .text:
        let text = try await self.client.send(TextDemoRequest())
        self.demoStates[demo] = DemoState(
          output: text,
          status: .passed,
          detail: "Read plain text without JSON decoding.",
          response: Self.responseSnapshot(
            title: "Plain text response",
            summary: "A string payload decoded through `ResponseSerializer.string`.",
            fields: [
              DemoInspectorField(label: "Format", value: "Text"),
              DemoInspectorField(label: "Expected status", value: "200")
            ],
            body: text
          )
        )
      case .empty:
        _ = try await self.client.send(EmptyDemoRequest())
        let output = "Received an EmptyResponse successfully."
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Validated a payload-free success response.",
          response: Self.responseSnapshot(
            title: "Empty response",
            summary: "A payload-free response validated through `EmptyResponse`.",
            fields: [
              DemoInspectorField(label: "Format", value: "Empty"),
              DemoInspectorField(label: "Expected status", value: "204")
            ],
            body: "No response body."
          )
        )
      case .raw:
        let raw = try await self.client.sendRaw(RawTodoRequest())
        let output = """
            status: \(raw.statusCode)
            content-type: \(raw.headers[.contentType] ?? "n/a")
            bytes: \(raw.data.count)

            \(String(decoding: raw.data, as: UTF8.self))
            """
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Inspected a raw response before decoding.",
          response: Self.responseSnapshot(
            title: "Raw HTTP response",
            summary: "A raw response inspected before serializer decoding.",
            fields: [
              DemoInspectorField(label: "Status", value: "\(raw.statusCode)"),
              DemoInspectorField(label: "Bytes", value: "\(raw.data.count)")
            ] + Self.headerFields(from: raw.headers),
            body: String(decoding: raw.data, as: UTF8.self)
          )
        )
      case .timeout:
        let output = try await self.expectedNetworkFailureOutput(
          request: TimeoutDemoRequest(mode: self.mode),
          expected: { $0.isTimeoutError },
          successSummary: "Observed the expected timeout failure."
        )
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Verified timeout handling and failure activity.",
          response: Self.responseSnapshot(
            title: "Timeout failure",
            summary: "The transport surfaced a timeout before a response body arrived.",
            fields: [
              DemoInspectorField(label: "Result", value: "Expected failure"),
              DemoInspectorField(label: "Error", value: "NetworkError.timeout")
            ],
            body: output
          )
        )
      case .unauthorized:
        let output = try await self.unauthorizedFailureOutput()
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Verified typed 401 decoding and raw HTTP preservation.",
          response: Self.responseSnapshot(
            title: "Typed error response",
            summary: "A structured HTTP error body decoded through `ErrorResponseSerializer`.",
            fields: [
              DemoInspectorField(label: "Result", value: "Expected HTTP failure"),
              DemoInspectorField(label: "Status", value: "401")
            ],
            body: output
          )
        )
      case .rateLimited:
        let output = try await self.rateLimitOutput()
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Verified retry middleware behavior for rate limiting.",
          response: Self.responseSnapshot(
            title: "Rate-limit result",
            summary: "Retry middleware either recovered after a 429 or preserved the final rate-limit response.",
            fields: [
              DemoInspectorField(label: "Result", value: self.mode == .mock ? "Recovered" : "HTTP 429")
            ],
            body: output
          )
        )
      case .serverError:
        let output = try await self.expectedNetworkFailureOutput(
          request: ServerErrorDemoRequest(mode: self.mode),
          expected: { $0.statusCode == 500 },
          successSummary: "Observed the expected server error."
        )
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Verified HTTP 500 status and body diagnostics.",
          response: Self.responseSnapshot(
            title: "Server error response",
            summary: "The response viewer preserves the HTTP failure body and status.",
            fields: [
              DemoInspectorField(label: "Result", value: "Expected HTTP failure"),
              DemoInspectorField(label: "Status", value: "500")
            ],
            body: output
          )
        )
      case .malformedJSON:
        let output = try await self.expectedNetworkFailureOutput(
          request: MalformedJSONDemoRequest(mode: self.mode),
          expected: { error in
            guard case .decoding = error else { return false }
            return true
          },
          successSummary: "Observed the expected decoding failure."
        )
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Verified malformed JSON decoding diagnostics.",
          response: Self.responseSnapshot(
            title: "Decoding failure",
            summary: "The HTTP response arrived but the JSON serializer rejected the payload shape.",
            fields: [
              DemoInspectorField(label: "Result", value: "Expected decoding failure"),
              DemoInspectorField(label: "Serializer", value: "ResponseSerializer.json")
            ],
            body: output
          )
        )
      case .cancelled:
        let output = try await self.cancellationOutput()
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Verified cancellation error normalization.",
          response: Self.responseSnapshot(
            title: "Cancellation result",
            summary: "The request was cancelled before a response body arrived.",
            fields: [
              DemoInspectorField(label: "Result", value: "Expected cancellation")
            ],
            body: output
          )
        )
      case .webSocket:
        let transcript = try await self.runWebSocketDemo()
        let output = Self.prettyPrintedJSON(for: transcript)
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Opened a socket, echoed JSON, and closed the session cleanly.",
          response: Self.responseSnapshot(
            title: "Socket transcript",
            summary: "A realtime exchange represented as a structured transcript.",
            fields: [
              DemoInspectorField(label: "Transport", value: transcript.transport),
              DemoInspectorField(label: "Close code", value: "\(transcript.closeCode)")
            ],
            body: output
          ),
          socket: Self.socketMonitorSnapshot(
            title: "WebSocket echo monitor",
            endpoint: transcript.endpoint,
            transport: transcript.transport,
            fields: [
              DemoInspectorField(
                label: "Subprotocol",
                value: transcript.negotiatedSubprotocol ?? "None"
              ),
              DemoInspectorField(label: "Close code", value: "\(transcript.closeCode)")
            ],
            frames: [
              DemoSocketFrame(
                direction: .outbound,
                title: "Sent text frame",
                payload: Self.prettyPrintedJSON(for: transcript.outbound)
              ),
              DemoSocketFrame(
                direction: .inbound,
                title: "Received text frame",
                payload: transcript.inboundText
              ),
              DemoSocketFrame(
                direction: .close,
                title: "Closed session",
                payload: "code \(transcript.closeCode)"
              )
            ]
          )
        )
      case .webSocketClose:
        let output = try await self.webSocketCloseOutput()
        self.demoStates[demo] = DemoState(
          output: output,
          status: .passed,
          detail: "Verified WebSocket close diagnostics.",
          response: Self.responseSnapshot(
            title: "Socket close result",
            summary: "The socket close frame was surfaced as a typed networking failure.",
            fields: [
              DemoInspectorField(label: "Result", value: "Expected close frame"),
              DemoInspectorField(label: "Close code", value: "\(WebSocketCloseCode.goingAway.rawValue)")
            ],
            body: output
          ),
          socket: Self.socketMonitorSnapshot(
            title: "WebSocket close monitor",
            endpoint: Self.socketCloseRequest().url.absoluteString,
            transport: "MockWebSocketTransport",
            fields: [
              DemoInspectorField(label: "Subprotocol", value: "comet.demo.v1"),
              DemoInspectorField(label: "Close code", value: "\(WebSocketCloseCode.goingAway.rawValue)")
            ],
            frames: [
              DemoSocketFrame(
                direction: .close,
                title: "Sent close frame",
                payload: "code \(WebSocketCloseCode.goingAway.rawValue), reason Demo close frame"
              ),
              DemoSocketFrame(
                direction: .inbound,
                title: "Receive after close",
                payload: output
              )
            ]
          )
        )
      }

      if var state = self.demoStates[demo] {
        state.cassette = await self.mockCassetteSnapshot(for: demo)
        self.demoStates[demo] = state
      }

      self.runSummary = "Latest success: \(demo.title) in \(self.mode.title) mode."
    } catch {
      if demo == .webSocket {
        self.recordSocketEvent(
          "failed socket",
          demo: demo,
          details: [
            self.mode.rawValue,
            error.localizedDescription
          ]
        )
      }
      self.demoStates[demo] = DemoState(
        output: "Error: \(error)",
        status: .failed,
        detail: "The demo failed before verification could complete.",
        response: Self.responseSnapshot(
          title: "Unexpected failure",
          summary: "The demo failed before its expected verifier completed.",
          fields: [
            DemoInspectorField(label: "Error", value: error.localizedDescription)
          ],
          body: "Error: \(error)"
        )
      )
      self.runSummary = "Latest failure: \(demo.title) in \(self.mode.title) mode."
    }
  }

  func runCurrentModeProof() async {
    for demo in Demo.allCases {
      await self.run(demo)
    }
  }

  func run(category: DemoCategory) async {
    for demo in category.demos {
      await self.run(demo)
    }
  }

  func runMockProof() async {
    if self.mode != .mock {
      self.mode = .mock
    }

    await self.runCurrentModeProof()
  }

  func clearSession() {
    self.demoStates = Self.makeInitialStates()
    self.activityLog.removeAll()
    self.runSummary = "Start in \(self.mode.title) mode and run the proof set to verify Comet end-to-end."
  }

  private func configureClient() {
    self.client = DemoClientFactory.makeClient(mode: self.mode)
    self.socketClient = DemoClientFactory.makeWebSocketClient(mode: self.mode)
    self.demoStates = Self.makeInitialStates()
    self.activityLog.removeAll()
    self.runSummary = "Switched to \(self.mode.title) mode. Run any scenario to verify the active transport."
    self.subscribeToActivity()
  }

  private func httpInspection<R: APIRequest>(
    for request: R,
    demo: Demo,
    client: HTTPClient? = nil,
    transport: String? = nil,
    extraFields: [DemoInspectorField] = []
  ) -> DemoRequestInspection {
    let inspectionClient = client ?? self.client
    let transport = transport ?? self.mode.httpTransportName
    let requestType = String(describing: R.self)

    do {
      let prepared = try inspectionClient.prepare(request)
      let metadata = request.options.metadata
      let metadataFields: [DemoInspectorField?] = [
        metadata.displayName.map { DemoInspectorField(label: "Metadata", value: $0) },
        metadata.tags.isEmpty
          ? nil
          : DemoInspectorField(label: "Tags", value: metadata.tags.joined(separator: ", "))
      ]
      let optionFields: [DemoInspectorField?] = [
        DemoInspectorField(label: "Path", value: request.path.rawValue.isEmpty ? "/" : request.path.rawValue),
        DemoInspectorField(label: "Response", value: String(describing: R.Response.self)),
        request.options.apiVersion.map { DemoInspectorField(label: "API version", value: $0) },
        request.options.absoluteURL.map { DemoInspectorField(label: "Absolute URL", value: $0.absoluteString) },
        request.options.idempotencyKey.map { DemoInspectorField(label: "Idempotency key", value: $0) },
        request.options.deduplicationKey.map { DemoInspectorField(label: "Deduplication key", value: $0) },
        request.options.retryPolicy == nil
          ? nil
          : DemoInspectorField(label: "Retry policy", value: "Request override")
      ]

      return DemoRequestInspection(
        title: demo.title,
        requestType: requestType,
        transport: transport,
        method: prepared.method.rawValue,
        url: prepared.url.absoluteString,
        timeout: Self.formattedDuration(prepared.timeout),
        fields: optionFields.compactMap { $0 }
          + metadataFields.compactMap { $0 }
          + extraFields
          + Self.headerFields(from: prepared.headers),
        bodyPreview: Self.bodyPreview(from: prepared.body),
        curlCommand: prepared.curlCommand(
          options: CURLCommandOptions(bodyFormatting: .prettyPrintedJSON)
        )
      )
    } catch {
      return DemoRequestInspection(
        title: demo.title,
        requestType: requestType,
        transport: transport,
        method: request.method.rawValue,
        url: "Unavailable",
        timeout: "Unavailable",
        fields: [
          DemoInspectorField(label: "Error", value: error.debugSummary)
        ],
        bodyPreview: "Request preparation failed.",
        curlCommand: nil
      )
    }
  }

  private func webSocketInspection(
    for request: WebSocketRequest,
    demo: Demo,
    transport: String
  ) -> DemoRequestInspection {
    let headers = Self.headerFields(from: request.headers)
    let subprotocols = request.subprotocols.isEmpty
      ? "None"
      : request.subprotocols.joined(separator: ", ")

    return DemoRequestInspection(
      title: demo.title,
      requestType: String(describing: WebSocketRequest.self),
      transport: transport,
      method: "GET",
      url: request.url.absoluteString,
      timeout: request.timeout.map(Self.formattedDuration) ?? "Default",
      fields: [
        DemoInspectorField(label: "Subprotocols", value: subprotocols),
        DemoInspectorField(label: "Message limit", value: "\(request.maximumMessageSize) bytes")
      ] + headers,
      bodyPreview: "WebSocket handshake only.",
      curlCommand: nil
    )
  }

  private func mockCassetteSnapshot(for demo: Demo) async -> DemoCassetteSnapshot? {
    guard self.mode == .mock else { return nil }
    guard demo.category != .realtime else { return nil }

    let recorder = RecordingTransport(
      base: DemoClientFactory.makeMockTransport(),
      now: { Date(timeIntervalSince1970: 1_782_595_200) }
    )
    let client = HTTPClient.live(
      configuration: DemoClientFactory.makeHTTPConfiguration(mode: .mock),
      transport: recorder
    )

    do {
      try await self.record(demo, with: client)
    } catch {
      // Expected failure scenarios are still recorded by RecordingTransport.
    }

    let cassette = await recorder.cassette()
    guard !cassette.exchanges.isEmpty else { return nil }

    do {
      let data = try cassette.encoded(prettyPrinted: true)
      let json = String(decoding: data, as: UTF8.self)
      return DemoCassetteSnapshot(
        title: "\(demo.title) cassette",
        summary: "A deterministic mock cassette exported from `RecordingTransport`.",
        fields: [
          DemoInspectorField(label: "Mode", value: self.mode.title),
          DemoInspectorField(label: "Exchanges", value: "\(cassette.exchanges.count)"),
          DemoInspectorField(
            label: "Outcomes",
            value: cassette.exchanges.map(Self.cassetteOutcomeLabel(for:)).joined(separator: ", ")
          )
        ],
        json: json
      )
    } catch {
      return DemoCassetteSnapshot(
        title: "\(demo.title) cassette",
        summary: "Cassette export failed.",
        fields: [
          DemoInspectorField(label: "Error", value: error.localizedDescription)
        ],
        json: "Cassette export failed: \(error)"
      )
    }
  }

  private func record(_ demo: Demo, with client: HTTPClient) async throws {
    switch demo {
    case .json:
      _ = try await client.send(TodoRequest())
    case .text:
      _ = try await client.send(TextDemoRequest())
    case .empty:
      _ = try await client.send(EmptyDemoRequest())
    case .raw:
      _ = try await client.sendRaw(RawTodoRequest())
    case .timeout:
      _ = try await client.send(TimeoutDemoRequest(mode: .mock))
    case .unauthorized:
      _ = try await client.sendWithTypedErrors(UnauthorizedDemoRequest(mode: .mock))
    case .rateLimited:
      _ = try await client.send(RateLimitDemoRequest(mode: .mock))
    case .serverError:
      _ = try await client.send(ServerErrorDemoRequest(mode: .mock))
    case .malformedJSON:
      _ = try await client.send(MalformedJSONDemoRequest(mode: .mock))
    case .cancelled:
      _ = try await client.send(CancelledDemoRequest())
    case .webSocket, .webSocketClose:
      return
    }
  }

  private func expectedNetworkFailureOutput<R: APIRequest>(
    request: R,
    expected: (NetworkError) -> Bool,
    successSummary: String
  ) async throws -> String {
    do {
      _ = try await self.client.send(request)
      throw NetworkError.invalidRequest("Expected the scenario to fail, but it succeeded.")
    } catch let error as NetworkError {
      guard expected(error) else { throw error }
      return Self.failureOutput(
        summary: successSummary,
        error: error
      )
    } catch {
      throw NetworkError.from(error)
    }
  }

  private func unauthorizedFailureOutput() async throws -> String {
    do {
      _ = try await self.client.sendWithTypedErrors(
        UnauthorizedDemoRequest(mode: self.mode)
      )
      throw NetworkError.invalidRequest("Expected the unauthorized scenario to fail, but it succeeded.")
    } catch let error as APIClientError<DemoAPIError> {
      switch error {
      case .api(let response):
        return """
          expected: decoded typed HTTP error
          status: \(response.statusCode)
          code: \(response.body.code)
          message: \(response.body.message)
          raw: \(response.networkError.debugSummary)
          """

      case .errorResponseDecodingFailed(let networkError, let decodingError):
        guard networkError.statusCode == 401 else { throw networkError }
        return """
          expected: HTTP 401 with undecodable live body
          status: \(networkError.statusCode?.formatted(.number) ?? "n/a")
          raw: \(networkError.debugSummary)
          decoder: \(decodingError.debugSummary)
          """

      case .network(let networkError):
        throw networkError
      }
    } catch {
      throw NetworkError.from(error)
    }
  }

  private func rateLimitOutput() async throws -> String {
    do {
      let response = try await self.client.send(
        RateLimitDemoRequest(mode: self.mode)
      )
      return """
        expected: recovered after retry
        response: \(response)
        activity: retry events appear in the activity tab
        """
    } catch {
      guard self.mode == .live, error.statusCode == 429 else { throw error }
      return Self.failureOutput(
        summary: "Observed the live rate-limit response after retries were exhausted.",
        error: error
      )
    }
  }

  private func cancellationOutput() async throws -> String {
    let cancellationClient = self.mode == .mock
      ? self.client
      : HTTPClient.failing(with: .cancelled)

    do {
      _ = try await cancellationClient.send(CancelledDemoRequest())
      throw NetworkError.invalidRequest("Expected the cancellation scenario to fail, but it succeeded.")
    } catch let error as NetworkError {
      guard error.isCancellationError else { throw error }
      return Self.failureOutput(
        summary: "Observed the expected cancellation failure.",
        error: error
      )
    } catch {
      throw NetworkError.from(error)
    }
  }

  private func runWebSocketDemo() async throws -> WebSocketDemoTranscript {
    let request = DemoClientFactory.makeWebSocketRequest(mode: self.mode)
    let payload = WebSocketDemoPayload(
      kind: "echo",
      mode: self.mode.rawValue,
      library: "Comet",
      note: self.mode == .mock
        ? "Mock echo routed through CometTesting."
        : "Live echo routed through URLSessionWebSocketTransport."
    )

    self.recordSocketEvent(
      "started socket",
      demo: .webSocket,
      details: [
        self.mode.rawValue,
        request.url.absoluteString
      ]
    )

    let connection = try await self.socketClient.connect(request)
    let outboundText = Self.prettyPrintedJSON(for: payload)

    try await connection.send(.text(outboundText))
    let reply = try await connection.receive()
    try await connection.close(code: .normalClosure, reason: Data("Comet demo complete".utf8))

    let inboundText = Self.messageText(from: reply)
    let inboundPayload = Self.decodeJSON(WebSocketDemoPayload.self, from: inboundText)

    self.recordSocketEvent(
      "completed socket",
      demo: .webSocket,
      details: [
        self.mode.rawValue,
        request.url.host() ?? request.url.absoluteString,
        "close \(WebSocketCloseCode.normalClosure.rawValue)"
      ]
    )

    return WebSocketDemoTranscript(
      endpoint: request.url.absoluteString,
      transport: self.mode == .mock ? "MockWebSocketTransport" : "URLSessionWebSocketTransport",
      negotiatedSubprotocol: connection.selectedSubprotocol,
      outbound: payload,
      inbound: inboundPayload,
      inboundText: inboundText,
      closeCode: WebSocketCloseCode.normalClosure.rawValue
    )
  }

  private func webSocketCloseOutput() async throws -> String {
    let sockets = WebSocketClient.live(
      transport: MockWebSocketTransport(
        selectedSubprotocol: "comet.demo.v1"
      )
    )
    let request = Self.socketCloseRequest()

    self.recordSocketEvent(
      "started close scenario",
      demo: .webSocketClose,
      details: [
        self.mode.rawValue,
        request.url.absoluteString
      ]
    )

    let connection = try await sockets.connect(request)
    try await connection.close(
      code: .goingAway,
      reason: Data("Demo close frame".utf8)
    )

    do {
      _ = try await connection.receive()
      throw NetworkError.invalidRequest("Expected receive after close to fail, but it succeeded.")
    } catch let error as NetworkError {
      guard case .webSocketClosed(let code, let reason) = error else {
        throw error
      }

      self.recordSocketEvent(
        "closed socket",
        demo: .webSocketClose,
        details: [
          "code \(code.rawValue)",
          String(data: reason ?? Data(), encoding: .utf8) ?? "no reason"
        ]
      )

      return Self.failureOutput(
        summary: "Observed the expected WebSocket close failure.",
        error: error
      )
    } catch {
      throw NetworkError.from(error)
    }
  }

  private func recordSocketEvent(_ title: String, demo: Demo, details: [String]) {
    self.activityLog.insert(
      Self.socketActivityEntry(title: title, demo: demo, details: details),
      at: 0
    )
  }

  private func subscribeToActivity() {
    let stream = self.client.activity
    self.activityObserver.task = Task { [weak self] in
      for await event in stream {
        guard !Task.isCancelled else { return }
        guard let self else { return }
        await MainActor.run {
          self.activityLog.insert(Self.activityEntry(for: event), at: 0)
        }
      }
    }
  }

  private static func makeInitialStates() -> [Demo: DemoState] {
    Dictionary(uniqueKeysWithValues: Demo.allCases.map { demo in
      (demo, Self.placeholderState(for: demo))
    })
  }

  private static func placeholderState(for demo: Demo) -> DemoState {
    switch demo {
    case .json:
      DemoState(
        output: "Run the JSON demo to decode a typed model.",
        status: .idle,
        detail: "Waiting for the first verification run."
      )
    case .text:
      DemoState(
        output: "Run the text demo to serialize plain text.",
        status: .idle,
        detail: "Waiting for the first verification run."
      )
    case .empty:
      DemoState(
        output: "Run the empty demo to validate a 204 response.",
        status: .idle,
        detail: "Waiting for the first verification run."
      )
    case .raw:
      DemoState(
        output: "Run the raw demo to inspect metadata.",
        status: .idle,
        detail: "Waiting for the first verification run."
      )
    case .timeout:
      DemoState(
        output: "Run the timeout demo to verify timeout handling.",
        status: .idle,
        detail: "Waiting for the first failure-gallery run."
      )
    case .unauthorized:
      DemoState(
        output: "Run the typed 401 demo to inspect decoded API errors.",
        status: .idle,
        detail: "Waiting for the first failure-gallery run."
      )
    case .rateLimited:
      DemoState(
        output: "Run the 429 demo to verify retry behavior.",
        status: .idle,
        detail: "Waiting for the first failure-gallery run."
      )
    case .serverError:
      DemoState(
        output: "Run the server error demo to inspect HTTP failure metadata.",
        status: .idle,
        detail: "Waiting for the first failure-gallery run."
      )
    case .malformedJSON:
      DemoState(
        output: "Run the malformed JSON demo to inspect decoding diagnostics.",
        status: .idle,
        detail: "Waiting for the first failure-gallery run."
      )
    case .cancelled:
      DemoState(
        output: "Run the cancellation demo to verify cancellation normalization.",
        status: .idle,
        detail: "Waiting for the first failure-gallery run."
      )
    case .webSocket:
      DemoState(
        output: "Run the WebSocket demo to inspect an echoed session transcript.",
        status: .idle,
        detail: "Waiting for the first verification run."
      )
    case .webSocketClose:
      DemoState(
        output: "Run the socket close demo to inspect close-frame diagnostics.",
        status: .idle,
        detail: "Waiting for the first realtime failure run."
      )
    }
  }

  private static func prettyPrintedJSON<Value: Encodable>(for value: Value) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
      let data = try encoder.encode(value)
      return String(decoding: data, as: UTF8.self)
    } catch {
      return String(describing: value)
    }
  }

  private static func decodeJSON<Value: Decodable>(_ type: Value.Type, from value: String) -> Value? {
    guard let data = value.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func failureOutput(
    summary: String,
    error: NetworkError
  ) -> String {
    """
    expected: \(summary)
    error: \(error.debugSummary)
    status: \(error.statusCode?.formatted(.number) ?? "n/a")
    body: \(error.bodyString ?? "n/a")
    """
  }

  private static func responseSnapshot(
    title: String,
    summary: String,
    fields: [DemoInspectorField],
    body: String
  ) -> DemoResponseSnapshot {
    let fieldLines = fields.map { "\($0.label): \($0.value)" }
    let rawValue = ([title, summary] + fieldLines + ["", body]).joined(separator: "\n")
    return DemoResponseSnapshot(
      title: title,
      summary: summary,
      fields: fields,
      body: body,
      rawValue: rawValue
    )
  }

  private static func socketMonitorSnapshot(
    title: String,
    endpoint: String,
    transport: String,
    fields: [DemoInspectorField],
    frames: [DemoSocketFrame]
  ) -> DemoSocketMonitorSnapshot {
    let baseFields = [
      DemoInspectorField(label: "Endpoint", value: endpoint),
      DemoInspectorField(label: "Transport", value: transport)
    ] + fields
    let frameLines = frames.map { frame in
      "[\(frame.direction.rawValue)] \(frame.title)\n\(frame.payload)"
    }
    let rawValue = ([title] + baseFields.map { "\($0.label): \($0.value)" } + [""] + frameLines)
      .joined(separator: "\n")
    return DemoSocketMonitorSnapshot(
      title: title,
      endpoint: endpoint,
      transport: transport,
      fields: baseFields,
      frames: frames,
      rawValue: rawValue
    )
  }

  private static func traceEntries(
    for demo: Demo,
    activityLog: [DemoActivityEntry]
  ) -> [DemoActivityEntry] {
    let matchingEntries = activityLog.filter { entry in
      if let metadataName = demo.traceMetadataName {
        return Self.fieldValue("Metadata", in: entry) == metadataName
      }

      return Self.fieldValue("Demo", in: entry) == demo.title
    }

    if demo.traceMetadataName != nil {
      guard let latestRequestID = matchingEntries.compactMap({ Self.fieldValue("Request ID", in: $0) }).first else {
        return []
      }

      return Array(
        matchingEntries
          .filter { Self.fieldValue("Request ID", in: $0) == latestRequestID }
          .reversed()
      )
    }

    let latestSessionEntries = Self.latestSocketSessionEntries(for: demo, entries: matchingEntries)
    return Array(latestSessionEntries.reversed())
  }

  private static func latestSocketSessionEntries(
    for demo: Demo,
    entries: [DemoActivityEntry]
  ) -> [DemoActivityEntry] {
    let startTitle = switch demo {
    case .webSocket:
      "started socket"
    case .webSocketClose:
      "started close scenario"
    default:
      ""
    }
    var sessionEntries: [DemoActivityEntry] = []

    for entry in entries {
      sessionEntries.append(entry)
      if entry.title == startTitle {
        break
      }
    }

    return sessionEntries
  }

  private static func traceTimeline(
    for demo: Demo,
    mode: ClientMode,
    entries: [DemoActivityEntry]
  ) -> DemoTraceTimeline? {
    guard !entries.isEmpty else { return nil }

    let requestIDs = Set(entries.compactMap { Self.fieldValue("Request ID", in: $0) })
      .sorted()
    let kinds = entries.map(\.kind.rawValue).joined(separator: " -> ")
    let correlation = requestIDs.isEmpty
      ? "Socket markers"
      : requestIDs.joined(separator: ", ")
    let fields = [
      DemoInspectorField(label: "Demo", value: demo.title),
      DemoInspectorField(label: "Mode", value: mode.title),
      DemoInspectorField(label: "Events", value: "\(entries.count)"),
      DemoInspectorField(label: "Correlation", value: correlation),
      DemoInspectorField(label: "Path", value: kinds)
    ]
    let title = "\(demo.title) trace"
    let summary = "Ordered activity events captured for the latest matching demo run."
    let eventLines = entries.map { entry in
      "[\(entry.kind.rawValue)] \(entry.rawValue)"
    }
    let rawValue = ([title, summary] + fields.map { "\($0.label): \($0.value)" } + [""] + eventLines)
      .joined(separator: "\n")

    return DemoTraceTimeline(
      title: title,
      summary: summary,
      fields: fields,
      events: entries,
      rawValue: rawValue
    )
  }

  private static func cassetteOutcomeLabel(for exchange: RecordedExchange) -> String {
    switch exchange.outcome {
    case .success(let response):
      "HTTP \(response.statusCode)"
    case .failure(let error):
      error.kind.rawValue
    }
  }

  private static func messageText(from message: WebSocketMessage) -> String {
    switch message {
    case .text(let value):
      return value
    case .data(let data):
      return String(decoding: data, as: UTF8.self)
    }
  }

  private static func socketCloseRequest() -> WebSocketRequest {
    WebSocketRequest(
      url: URL(string: "wss://comet.local/socket-close")!,
      subprotocols: ["comet.demo.v1"],
      timeout: .seconds(10)
    )
  }

  private static func activityEntry(for event: NetworkEvent) -> DemoActivityEntry {
    let shortID = String(event.id.uuidString.prefix(8))
    let name = event.displayName ?? "Request"
    let metadata = event.metadata
    var fields = [
      DemoInspectorField(label: "Request ID", value: shortID)
    ]

    if let displayName = metadata.displayName {
      fields.append(DemoInspectorField(label: "Metadata", value: displayName))
    }
    if !metadata.tags.isEmpty {
      fields.append(DemoInspectorField(label: "Tags", value: metadata.tags.joined(separator: ", ")))
    }

    switch event {
    case .requestStarted(_, let method, let url, _):
      fields.append(DemoInspectorField(label: "Method", value: method.rawValue))
      fields.append(DemoInspectorField(label: "URL", value: url.absoluteString))
      let title = "\(name) started"
      let detail = "\(method.rawValue) \(url.absoluteString)"
      return DemoActivityEntry(
        kind: .started,
        title: title,
        detail: detail,
        fields: fields,
        rawValue: ([title, "id \(shortID)", detail]).joined(separator: " • ")
      )

    case .requestCompleted(_, let statusCode, let duration, _):
      let formattedDuration = Self.formattedDuration(duration)
      fields.append(DemoInspectorField(label: "Status", value: "\(statusCode)"))
      fields.append(DemoInspectorField(label: "Duration", value: formattedDuration))
      let title = "\(name) completed"
      let detail = "HTTP \(statusCode) in \(formattedDuration)"
      return DemoActivityEntry(
        kind: .completed,
        title: title,
        detail: detail,
        fields: fields,
        rawValue: ([title, "id \(shortID)", detail]).joined(separator: " • ")
      )

    case .requestFailed(_, let error, let duration, _):
      let formattedDuration = Self.formattedDuration(duration)
      fields.append(DemoInspectorField(label: "Duration", value: formattedDuration))
      fields.append(DemoInspectorField(label: "Error", value: error.debugSummary))
      if let statusCode = error.statusCode {
        fields.append(DemoInspectorField(label: "Status", value: "\(statusCode)"))
      }
      if let bodyString = error.bodyString, !bodyString.isEmpty {
        fields.append(DemoInspectorField(label: "Body", value: bodyString))
      }
      let title = "\(name) failed"
      let detail = "\(error.debugSummary) in \(formattedDuration)"
      return DemoActivityEntry(
        kind: .failed,
        title: title,
        detail: detail,
        fields: fields,
        rawValue: ([title, "id \(shortID)", detail]).joined(separator: " • ")
      )

    case .requestRetried(_, let attempt, let delay, _):
      let formattedDelay = Self.formattedDuration(delay)
      fields.append(DemoInspectorField(label: "Attempt", value: "\(attempt)"))
      fields.append(DemoInspectorField(label: "Delay", value: formattedDelay))
      let title = "\(name) retry"
      let detail = "Attempt \(attempt) after \(formattedDelay)"
      return DemoActivityEntry(
        kind: .retried,
        title: title,
        detail: detail,
        fields: fields,
        rawValue: ([title, "id \(shortID)", detail]).joined(separator: " • ")
      )
    }
  }

  private static func socketActivityEntry(
    title: String,
    demo: Demo,
    details: [String]
  ) -> DemoActivityEntry {
    let fields = [DemoInspectorField(label: "Demo", value: demo.title)]
      + details.enumerated().map { index, value in
        DemoInspectorField(label: "Detail \(index + 1)", value: value)
      }
    let rawValue = ([title] + details).joined(separator: " • ")
    return DemoActivityEntry(
      kind: .socket,
      title: title,
      detail: details.joined(separator: " • "),
      fields: fields,
      rawValue: rawValue
    )
  }

  private static func fieldValue(_ label: String, in entry: DemoActivityEntry) -> String? {
    entry.fields.first { $0.label == label }?.value
  }

  private static func headerFields(from headers: HTTPFields) -> [DemoInspectorField] {
    let fields = headers
      .map { field in
        DemoInspectorField(
          label: "Header",
          value: "\(field.name.canonicalName): \(field.value)"
        )
      }
      .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }

    return fields.isEmpty
      ? [DemoInspectorField(label: "Headers", value: "None")]
      : fields
  }

  private static func bodyPreview(from body: Data?) -> String {
    guard let body, !body.isEmpty else {
      return "No request body."
    }
    if let prettyJSON = Self.prettyPrintedJSONString(from: body) {
      return prettyJSON
    }
    if let string = String(data: body, encoding: .utf8) {
      return string
    }
    return "Binary body: \(body.count) bytes."
  }

  private static func prettyPrintedJSONString(from data: Data) -> String? {
    let trimmed = String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.first == "{" || trimmed.first == "[" else { return nil }

    do {
      let object = try JSONSerialization.jsonObject(with: data)
      let prettyData = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
      )
      return String(decoding: prettyData, as: UTF8.self)
    } catch {
      return nil
    }
  }

  private static func formattedDuration(_ duration: Duration) -> String {
    duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
  }
}

private extension DemoCatalog.ClientMode {
  var httpTransportName: String {
    switch self {
    case .mock:
      "MockTransport"
    case .live:
      "URLSessionTransport"
    }
  }

  var webSocketTransportName: String {
    switch self {
    case .mock:
      "MockWebSocketTransport"
    case .live:
      "URLSessionWebSocketTransport"
    }
  }
}

private final class ActivityObserver {
  var task: Task<Void, Never>? {
    willSet {
      self.task?.cancel()
    }
  }

  deinit {
    self.task?.cancel()
  }
}
