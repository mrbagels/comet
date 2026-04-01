import Foundation
import Observation
import Comet

@MainActor
@Observable
final class DemoCatalog {
  enum DemoCategory: String, CaseIterable, Identifiable {
    case requests
    case transport
    case realtime

    var id: String { self.rawValue }

    var title: String {
      switch self {
      case .requests: "Requests"
      case .transport: "Transport"
      case .realtime: "Realtime"
      }
    }

    var subtitle: String {
      switch self {
      case .requests:
        "Typed serialization, URL shaping, and content transforms."
      case .transport:
        "Status validation, raw inspection, and payload-free flows."
      case .realtime:
        "Bidirectional sessions, echo transcripts, and socket transport swaps."
      }
    }

    var symbolName: String {
      switch self {
      case .requests: "point.3.connected.trianglepath.dotted"
      case .transport: "waveform.path.ecg.rectangle"
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
    case webSocket

    var id: String { self.rawValue }

    var title: String {
      switch self {
      case .json: "Typed JSON"
      case .text: "Plain Text"
      case .empty: "Empty Response"
      case .raw: "Raw Response"
      case .webSocket: "WebSocket Echo"
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
      case .webSocket:
        "Open a socket, send JSON, and inspect the echoed transcript with the WebSocket client surface."
      }
    }

    var category: DemoCategory {
      switch self {
      case .json, .text:
        .requests
      case .empty, .raw:
        .transport
      case .webSocket:
        .realtime
      }
    }

    var symbolName: String {
      switch self {
      case .json: "sparkles.rectangle.stack"
      case .text: "text.page"
      case .empty: "checkmark.circle.badge.xmark"
      case .raw: "bolt.horizontal.circle"
      case .webSocket: "dot.radiowaves.up.forward"
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
      case .webSocket:
        [
          "WebSocketClient.connect",
          "WebSocketRequest",
          "URLSessionWebSocketTransport",
          "MockWebSocketTransport"
        ]
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
  }

  var mode: ClientMode = .mock {
    didSet {
      guard oldValue != mode else { return }
      self.configureClient()
    }
  }

  private(set) var demoStates: [Demo: DemoState]
  var activityLog: [String] = []
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

  func run(_ demo: Demo) async {
    self.demoStates[demo]?.status = .running
    self.demoStates[demo]?.detail = "Request in flight..."

    do {
      switch demo {
      case .json:
        let todo = try await self.client.send(TodoRequest())
        self.demoStates[demo] = DemoState(
          output: Self.prettyPrintedJSON(for: todo),
          status: .passed,
          detail: "Decoded a typed `DemoTodo` and rendered formatted JSON."
        )
      case .text:
        let text = try await self.client.send(TextDemoRequest())
        self.demoStates[demo] = DemoState(
          output: text,
          status: .passed,
          detail: "Read plain text without JSON decoding."
        )
      case .empty:
        _ = try await self.client.send(EmptyDemoRequest())
        self.demoStates[demo] = DemoState(
          output: "Received an EmptyResponse successfully.",
          status: .passed,
          detail: "Validated a payload-free success response."
        )
      case .raw:
        let raw = try await self.client.sendRaw(RawTodoRequest())
        self.demoStates[demo] = DemoState(
          output: """
            status: \(raw.statusCode)
            content-type: \(raw.headers[.contentType] ?? "n/a")
            bytes: \(raw.data.count)

            \(String(decoding: raw.data, as: UTF8.self))
            """,
          status: .passed,
          detail: "Inspected a raw response before decoding."
        )
      case .webSocket:
        let transcript = try await self.runWebSocketDemo()
        self.demoStates[demo] = DemoState(
          output: Self.prettyPrintedJSON(for: transcript),
          status: .passed,
          detail: "Opened a socket, echoed JSON, and closed the session cleanly."
        )
      }

      self.runSummary = "Latest success: \(demo.title) in \(self.mode.title) mode."
    } catch {
      if demo == .webSocket {
        self.recordSocketEvent(
          "failed socket",
          details: [
            self.mode.rawValue,
            error.localizedDescription
          ]
        )
      }
      self.demoStates[demo] = DemoState(
        output: "Error: \(error)",
        status: .failed,
        detail: "The demo failed before verification could complete."
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

  private func recordSocketEvent(_ title: String, details: [String]) {
    self.activityLog.insert(
      ([title] + details).joined(separator: " • "),
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
          self.activityLog.insert(Self.describe(event), at: 0)
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
    case .webSocket:
      DemoState(
        output: "Run the WebSocket demo to inspect an echoed session transcript.",
        status: .idle,
        detail: "Waiting for the first verification run."
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

  private static func messageText(from message: WebSocketMessage) -> String {
    switch message {
    case .text(let value):
      return value
    case .data(let data):
      return String(decoding: data, as: UTF8.self)
    }
  }

  private static func describe(_ event: NetworkEvent) -> String {
    switch event {
    case .requestStarted(let id, let method, let url):
      return "\(method.rawValue) started • \(id.uuidString.prefix(8)) • \(url.absoluteString)"
    case .requestCompleted(let id, let statusCode, let duration):
      return "completed \(statusCode) • \(id.uuidString.prefix(8)) • \(duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))"
    case .requestFailed(let id, let error, let duration):
      return "failed • \(id.uuidString.prefix(8)) • \(duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))) • \(error)"
    case .requestRetried(let id, let attempt, let delay):
      return "retry \(attempt) • \(id.uuidString.prefix(8)) • \(delay.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))"
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
