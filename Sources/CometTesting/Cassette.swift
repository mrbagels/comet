import Foundation
import HTTPTypes
import Comet

/// A JSON-serializable collection of recorded HTTP exchanges.
public struct HTTPCassette: Codable, Sendable, Hashable {
  public var recordedAt: Date
  public var exchanges: [RecordedExchange]

  /// Creates a cassette from a list of recorded exchanges.
  public init(
    recordedAt: Date = Date(),
    exchanges: [RecordedExchange]
  ) {
    self.recordedAt = recordedAt
    self.exchanges = exchanges
  }

  /// Loads a cassette from disk.
  public init(
    contentsOf url: URL,
    decoder: JSONDecoder = Self.jsonDecoder()
  ) throws {
    let data = try Data(contentsOf: url)
    self = try decoder.decode(Self.self, from: data)
  }

  /// Encodes the cassette as JSON data.
  public func encoded(prettyPrinted: Bool = true) throws -> Data {
    try Self.jsonEncoder(prettyPrinted: prettyPrinted).encode(self)
  }

  /// Writes the cassette to disk as JSON.
  public func write(
    to url: URL,
    prettyPrinted: Bool = true
  ) throws {
    try self.encoded(prettyPrinted: prettyPrinted).write(to: url, options: .atomic)
  }

  /// Builds the JSON encoder used for cassette export.
  public static func jsonEncoder(prettyPrinted: Bool = true) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if prettyPrinted {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    return encoder
  }

  /// Builds the JSON decoder used for cassette import.
  public static func jsonDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

/// A single recorded request plus its response or failure.
public struct RecordedExchange: Codable, Sendable, Hashable {
  public var recordedAt: Date
  public var request: RecordedRequest
  public var durationMilliseconds: Int64
  public var outcome: Outcome

  /// Creates a recorded exchange from a request and its outcome.
  public init(
    recordedAt: Date = Date(),
    request: RecordedRequest,
    duration: Duration,
    outcome: Outcome
  ) {
    self.recordedAt = recordedAt
    self.request = request
    self.durationMilliseconds = duration.millisecondsValue
    self.outcome = outcome
  }

  /// Returns the recorded duration as ``Swift/Duration``.
  public var duration: Duration {
    .milliseconds(self.durationMilliseconds)
  }

  func replay() throws(NetworkError) -> RawResponse {
    switch self.outcome {
    case .success(let response):
      return try response.makeRawResponse()
    case .failure(let error):
      let networkError = try error.makeNetworkError()
      throw networkError
    }
  }
}

public extension RecordedExchange {
  /// The recorded outcome of an exchange.
  enum Outcome: Codable, Sendable, Hashable {
    case success(RecordedResponse)
    case failure(RecordedNetworkError)

    private enum CodingKeys: String, CodingKey {
      case kind
      case response
      case error
    }

    private enum Kind: String, Codable {
      case success
      case failure
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      switch try container.decode(Kind.self, forKey: .kind) {
      case .success:
        self = .success(try container.decode(RecordedResponse.self, forKey: .response))
      case .failure:
        self = .failure(try container.decode(RecordedNetworkError.self, forKey: .error))
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .success(let response):
        try container.encode(Kind.success, forKey: .kind)
        try container.encode(response, forKey: .response)
      case .failure(let error):
        try container.encode(Kind.failure, forKey: .kind)
        try container.encode(error, forKey: .error)
      }
    }
  }
}

/// A JSON-friendly representation of a prepared request.
public struct RecordedRequest: Codable, Sendable, Hashable {
  public var method: String
  public var url: String
  public var headers: [RecordedHeader]
  public var bodyBase64: String?
  public var timeoutMilliseconds: Int64
  public var bodyWasRedacted: Bool

  /// Creates a recorded request from individual components.
  public init(
    method: String,
    url: String,
    headers: [RecordedHeader] = [],
    bodyBase64: String? = nil,
    timeoutMilliseconds: Int64,
    bodyWasRedacted: Bool = false
  ) {
    self.method = method
    self.url = url
    self.headers = headers
    self.bodyBase64 = bodyBase64
    self.timeoutMilliseconds = timeoutMilliseconds
    self.bodyWasRedacted = bodyWasRedacted
  }

  /// Snapshots a prepared request for storage in a cassette.
  public init(
    _ request: PreparedRequest,
    redaction: RecordingRedaction = RecordingRedaction()
  ) {
    let body = redaction.recordedRequestBody(for: request)
    self.init(
      method: request.method.rawValue,
      url: request.url.absoluteString,
      headers: request.headers.recordedHeaders(redaction: redaction),
      bodyBase64: body.data?.base64EncodedString(),
      timeoutMilliseconds: request.timeout.millisecondsValue,
      bodyWasRedacted: body.wasRedacted
    )
  }

  private enum CodingKeys: String, CodingKey {
    case method
    case url
    case headers
    case bodyBase64
    case timeoutMilliseconds
    case bodyWasRedacted
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.method = try container.decode(String.self, forKey: .method)
    self.url = try container.decode(String.self, forKey: .url)
    self.headers = try container.decode([RecordedHeader].self, forKey: .headers)
    self.bodyBase64 = try container.decodeIfPresent(String.self, forKey: .bodyBase64)
    self.timeoutMilliseconds = try container.decode(Int64.self, forKey: .timeoutMilliseconds)
    self.bodyWasRedacted = try container.decodeIfPresent(Bool.self, forKey: .bodyWasRedacted) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.method, forKey: .method)
    try container.encode(self.url, forKey: .url)
    try container.encode(self.headers, forKey: .headers)
    try container.encodeIfPresent(self.bodyBase64, forKey: .bodyBase64)
    try container.encode(self.timeoutMilliseconds, forKey: .timeoutMilliseconds)
    try container.encode(self.bodyWasRedacted, forKey: .bodyWasRedacted)
  }

  /// Returns the decoded request body when one was recorded.
  public var bodyData: Data? {
    self.bodyBase64.flatMap { Data(base64Encoded: $0) }
  }

  /// Returns whether the recorded request matches a prepared request for replay.
  public func matches(_ request: PreparedRequest) -> Bool {
    if self.bodyBase64 != nil && self.bodyData == nil {
      return false
    }
    return self.method == request.method.rawValue
      && self.url == request.url.absoluteString
      && (self.bodyWasRedacted || self.bodyData == request.body)
  }

  /// Reconstructs the prepared request represented by this snapshot.
  public func makePreparedRequest() throws(NetworkError) -> PreparedRequest {
    guard let url = URL(string: self.url) else {
      throw .invalidRequest("Cassette contains an invalid request URL: \(self.url)")
    }
    let method = HTTPMethod(rawValue: self.method)

    return try PreparedRequest(
      url: url,
      method: method,
      headers: HTTPFields(recordedHeaders: self.headers),
      body: self.decodedBodyData(),
      timeout: .milliseconds(self.timeoutMilliseconds)
    )
  }

  private func decodedBodyData() throws(NetworkError) -> Data? {
    guard let bodyBase64 else { return nil }
    guard let data = Data(base64Encoded: bodyBase64) else {
      throw .invalidRequest("Cassette contains invalid request body base64.")
    }
    return data
  }
}

/// A JSON-friendly representation of a raw HTTP response.
public struct RecordedResponse: Codable, Sendable, Hashable {
  public var statusCode: Int
  public var headers: [RecordedHeader]
  public var bodyBase64: String
  public var bodyWasRedacted: Bool

  /// Creates a recorded response from individual components.
  public init(
    statusCode: Int,
    headers: [RecordedHeader] = [],
    bodyBase64: String,
    bodyWasRedacted: Bool = false
  ) {
    self.statusCode = statusCode
    self.headers = headers
    self.bodyBase64 = bodyBase64
    self.bodyWasRedacted = bodyWasRedacted
  }

  /// Snapshots a raw response for storage in a cassette.
  public init(
    _ response: RawResponse,
    redaction: RecordingRedaction = RecordingRedaction()
  ) {
    let body = redaction.recordedResponseBody(for: response)
    self.init(
      statusCode: response.statusCode,
      headers: response.headers.recordedHeaders(redaction: redaction),
      bodyBase64: body.data.base64EncodedString(),
      bodyWasRedacted: body.wasRedacted
    )
  }

  private enum CodingKeys: String, CodingKey {
    case statusCode
    case headers
    case bodyBase64
    case bodyWasRedacted
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.statusCode = try container.decode(Int.self, forKey: .statusCode)
    self.headers = try container.decode([RecordedHeader].self, forKey: .headers)
    self.bodyBase64 = try container.decode(String.self, forKey: .bodyBase64)
    self.bodyWasRedacted = try container.decodeIfPresent(Bool.self, forKey: .bodyWasRedacted) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.statusCode, forKey: .statusCode)
    try container.encode(self.headers, forKey: .headers)
    try container.encode(self.bodyBase64, forKey: .bodyBase64)
    try container.encode(self.bodyWasRedacted, forKey: .bodyWasRedacted)
  }

  /// Returns the decoded response body.
  public var bodyData: Data {
    Data(base64Encoded: self.bodyBase64) ?? Data()
  }

  /// Reconstructs the raw response represented by this snapshot.
  public func makeRawResponse() throws(NetworkError) -> RawResponse {
    try RawResponse(
      data: self.decodedBodyData(),
      statusCode: self.statusCode,
      headers: HTTPFields(recordedHeaders: self.headers)
    )
  }

  private func decodedBodyData() throws(NetworkError) -> Data {
    guard let data = Data(base64Encoded: self.bodyBase64) else {
      throw .invalidRequest("Cassette contains invalid response body base64.")
    }
    return data
  }
}

/// A JSON-friendly representation of a ``NetworkError``.
public struct RecordedNetworkError: Codable, Sendable, Hashable {
  /// The stored error category used for replay.
  public enum Kind: String, Codable, Sendable, Hashable {
    case invalidRequest
    case transport
    case http
    case webSocketClosed
    case decoding
    case encoding
    case middleware
    case cancelled
    case timeout
    case unknown
  }

  public var kind: Kind
  public var message: String?
  public var statusCode: Int?
  public var headers: [RecordedHeader]
  public var bodyBase64: String?
  public var urlErrorCode: Int?

  /// Creates a recorded error from individual components.
  public init(
    kind: Kind,
    message: String? = nil,
    statusCode: Int? = nil,
    headers: [RecordedHeader] = [],
    bodyBase64: String? = nil,
    urlErrorCode: Int? = nil
  ) {
    self.kind = kind
    self.message = message
    self.statusCode = statusCode
    self.headers = headers
    self.bodyBase64 = bodyBase64
    self.urlErrorCode = urlErrorCode
  }

  /// Snapshots a runtime ``NetworkError`` for storage in a cassette.
  public init(
    _ error: NetworkError,
    redaction: RecordingRedaction = RecordingRedaction()
  ) {
    switch error {
    case .invalidRequest(let message):
      self.init(kind: .invalidRequest, message: message)
    case .transport(let urlError):
      self.init(
        kind: .transport,
        message: urlError.localizedDescription,
        urlErrorCode: urlError.code.rawValue
      )
    case .http(let statusCode, let body, let headers):
      let recordedBody = redaction.recordedResponseBody(
        for: RawResponse(data: body, statusCode: statusCode, headers: headers)
      )
      self.init(
        kind: .http,
        statusCode: statusCode,
        headers: headers.recordedHeaders(redaction: redaction),
        bodyBase64: recordedBody.data.base64EncodedString()
      )
    case .webSocketClosed(let code, let reason):
      self.init(
        kind: .webSocketClosed,
        statusCode: Int(code.rawValue),
        bodyBase64: reason?.base64EncodedString()
      )
    case .decoding(let error):
      self.init(kind: .decoding, message: String(describing: error))
    case .encoding(let message):
      self.init(kind: .encoding, message: message)
    case .middleware(let message):
      self.init(kind: .middleware, message: message)
    case .cancelled:
      self.init(kind: .cancelled)
    case .timeout:
      self.init(kind: .timeout)
    case .unknown(let error):
      self.init(kind: .unknown, message: String(describing: error))
    }
  }

  /// Returns the decoded error body when one was recorded.
  public var bodyData: Data? {
    self.bodyBase64.flatMap { Data(base64Encoded: $0) }
  }

  /// Reconstructs the runtime ``NetworkError`` represented by this snapshot.
  public var networkError: NetworkError {
    (try? self.makeNetworkError())
      ?? .invalidRequest("Cassette contains an invalid recorded network error.")
  }

  /// Reconstructs the runtime ``NetworkError`` represented by this snapshot.
  public func makeNetworkError() throws(NetworkError) -> NetworkError {
    switch self.kind {
    case .invalidRequest:
      return .invalidRequest(self.message ?? "Recorded invalid request")
    case .transport:
      return .transport(URLError(.init(rawValue: self.urlErrorCode ?? NSURLErrorUnknown)))
    case .http:
      return .http(
        statusCode: self.statusCode ?? 0,
        body: try self.decodedBodyData() ?? Data(),
        headers: try HTTPFields(recordedHeaders: self.headers)
      )
    case .webSocketClosed:
      return .webSocketClosed(
        code: WebSocketCloseCode(
          rawValue: UInt16(exactly: self.statusCode ?? Int(WebSocketCloseCode.normalClosure.rawValue))
            ?? WebSocketCloseCode.normalClosure.rawValue
        ),
        reason: try self.decodedBodyData()
      )
    case .decoding:
      return .decoding(
        DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: self.message ?? "Recorded decoding failure")
        )
      )
    case .encoding:
      return .encoding(self.message ?? "Recorded encoding failure")
    case .middleware:
      return .middleware(self.message ?? "Recorded middleware failure")
    case .cancelled:
      return .cancelled
    case .timeout:
      return .timeout
    case .unknown:
      return .unknown(
        NSError(
          domain: "CometTesting.RecordedNetworkError",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: self.message ?? "Recorded unknown failure"]
        )
      )
    }
  }

  private func decodedBodyData() throws(NetworkError) -> Data? {
    guard let bodyBase64 else { return nil }
    guard let data = Data(base64Encoded: bodyBase64) else {
      throw .invalidRequest("Cassette contains invalid error body base64.")
    }
    return data
  }
}

/// A single HTTP header stored in a JSON-friendly form.
public struct RecordedHeader: Codable, Sendable, Hashable {
  public var name: String
  public var value: String

  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

/// Replays a previously recorded cassette as an ``HTTPTransport``.
public actor ReplayTransport: HTTPTransport {
  /// Controls how cassette entries are matched during replay.
  public enum Mode: Sendable {
    case matchingRequest
    case sequential
  }

  private let cassette: HTTPCassette
  private let mode: Mode
  private var remainingExchanges: [RecordedExchange]

  /// Creates a replay transport from an in-memory cassette.
  public init(
    cassette: HTTPCassette,
    mode: Mode = .matchingRequest
  ) {
    self.cassette = cassette
    self.mode = mode
    self.remainingExchanges = cassette.exchanges
  }

  /// Loads a replay transport from a cassette on disk.
  public init(
    contentsOf url: URL,
    mode: Mode = .matchingRequest,
    decoder: JSONDecoder = HTTPCassette.jsonDecoder()
  ) throws {
    let cassette = try HTTPCassette(contentsOf: url, decoder: decoder)
    self.init(cassette: cassette, mode: mode)
  }

  /// Replays the next matching recorded exchange.
  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    let exchange: RecordedExchange

    switch self.mode {
    case .matchingRequest:
      guard let index = self.remainingExchanges.firstIndex(where: { $0.request.matches(request) }) else {
        throw .invalidRequest("No recorded exchange matched \(request.method.rawValue) \(request.url.absoluteString).")
      }
      exchange = self.remainingExchanges.remove(at: index)

    case .sequential:
      guard !self.remainingExchanges.isEmpty else {
        throw .invalidRequest("No recorded exchanges remain in the cassette.")
      }
      exchange = self.remainingExchanges.removeFirst()

      guard exchange.request.matches(request) else {
        throw .invalidRequest(
          """
          The next recorded exchange was \(exchange.request.method) \(exchange.request.url), \
          but the request was \(request.method.rawValue) \(request.url.absoluteString).
          """
        )
      }
    }

    return try exchange.replay()
  }

  /// Returns the number of recorded exchanges that have not been consumed yet.
  public func remainingCount() -> Int {
    self.remainingExchanges.count
  }

  /// Restores the replay transport to its initial, fully unconsumed state.
  public func reset() {
    self.remainingExchanges = self.cassette.exchanges
  }
}

private extension HTTPFields {
  init(recordedHeaders: [RecordedHeader]) throws(NetworkError) {
    self.init()
    for header in recordedHeaders {
      guard let name = HTTPField.Name(header.name) else {
        throw .invalidRequest("Cassette contains an invalid header name: \(header.name)")
      }
      self.append(HTTPField(name: name, value: header.value))
    }
  }

  var recordedHeaders: [RecordedHeader] {
    self.recordedHeaders(redaction: RecordingRedaction(redactedHeaders: []))
  }

  func recordedHeaders(redaction: RecordingRedaction) -> [RecordedHeader] {
    self.map { field in
      let name = field.name.rawName
      return RecordedHeader(
        name: name,
        value: redaction.redacts(headerName: name) ? "<redacted>" : field.value
      )
    }
  }
}

private extension Duration {
  var millisecondsValue: Int64 {
    let components = self.components
    return components.seconds * 1_000
      + Int64(Double(components.attoseconds) / 1_000_000_000_000_000)
  }
}
