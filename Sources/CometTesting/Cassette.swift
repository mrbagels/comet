import Foundation
import HTTPTypes
import Comet

public struct HTTPCassette: Codable, Sendable, Hashable {
  public var recordedAt: Date
  public var exchanges: [RecordedExchange]

  public init(
    recordedAt: Date = Date(),
    exchanges: [RecordedExchange]
  ) {
    self.recordedAt = recordedAt
    self.exchanges = exchanges
  }

  public init(
    contentsOf url: URL,
    decoder: JSONDecoder = Self.jsonDecoder()
  ) throws {
    let data = try Data(contentsOf: url)
    self = try decoder.decode(Self.self, from: data)
  }

  public func encoded(prettyPrinted: Bool = true) throws -> Data {
    try Self.jsonEncoder(prettyPrinted: prettyPrinted).encode(self)
  }

  public func write(
    to url: URL,
    prettyPrinted: Bool = true
  ) throws {
    try self.encoded(prettyPrinted: prettyPrinted).write(to: url, options: .atomic)
  }

  public static func jsonEncoder(prettyPrinted: Bool = true) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if prettyPrinted {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    return encoder
  }

  public static func jsonDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

public struct RecordedExchange: Codable, Sendable, Hashable {
  public var recordedAt: Date
  public var request: RecordedRequest
  public var durationMilliseconds: Int64
  public var outcome: Outcome

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

  public var duration: Duration {
    .milliseconds(self.durationMilliseconds)
  }

  func replay() throws(NetworkError) -> RawResponse {
    switch self.outcome {
    case .success(let response):
      return try response.makeRawResponse()
    case .failure(let error):
      throw error.networkError
    }
  }
}

public extension RecordedExchange {
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

public struct RecordedRequest: Codable, Sendable, Hashable {
  public var method: String
  public var url: String
  public var headers: [RecordedHeader]
  public var bodyBase64: String?
  public var timeoutMilliseconds: Int64

  public init(
    method: String,
    url: String,
    headers: [RecordedHeader] = [],
    bodyBase64: String? = nil,
    timeoutMilliseconds: Int64
  ) {
    self.method = method
    self.url = url
    self.headers = headers
    self.bodyBase64 = bodyBase64
    self.timeoutMilliseconds = timeoutMilliseconds
  }

  public init(_ request: PreparedRequest) {
    self.init(
      method: request.method.rawValue,
      url: request.url.absoluteString,
      headers: request.headers.recordedHeaders,
      bodyBase64: request.body?.base64EncodedString(),
      timeoutMilliseconds: request.timeout.millisecondsValue
    )
  }

  public var bodyData: Data? {
    self.bodyBase64.flatMap { Data(base64Encoded: $0) }
  }

  public func matches(_ request: PreparedRequest) -> Bool {
    self.method == request.method.rawValue
      && self.url == request.url.absoluteString
      && self.bodyData == request.body
  }

  public func makePreparedRequest() throws(NetworkError) -> PreparedRequest {
    guard let url = URL(string: self.url) else {
      throw .invalidRequest("Cassette contains an invalid request URL: \(self.url)")
    }
    let method = HTTPMethod(rawValue: self.method)

    return try PreparedRequest(
      url: url,
      method: method,
      headers: HTTPFields(recordedHeaders: self.headers),
      body: self.bodyData,
      timeout: .milliseconds(self.timeoutMilliseconds)
    )
  }
}

public struct RecordedResponse: Codable, Sendable, Hashable {
  public var statusCode: Int
  public var headers: [RecordedHeader]
  public var bodyBase64: String

  public init(
    statusCode: Int,
    headers: [RecordedHeader] = [],
    bodyBase64: String
  ) {
    self.statusCode = statusCode
    self.headers = headers
    self.bodyBase64 = bodyBase64
  }

  public init(_ response: RawResponse) {
    self.init(
      statusCode: response.statusCode,
      headers: response.headers.recordedHeaders,
      bodyBase64: response.data.base64EncodedString()
    )
  }

  public var bodyData: Data {
    Data(base64Encoded: self.bodyBase64) ?? Data()
  }

  public func makeRawResponse() throws(NetworkError) -> RawResponse {
    try RawResponse(
      data: self.bodyData,
      statusCode: self.statusCode,
      headers: HTTPFields(recordedHeaders: self.headers)
    )
  }
}

public struct RecordedNetworkError: Codable, Sendable, Hashable {
  public enum Kind: String, Codable, Sendable, Hashable {
    case invalidRequest
    case transport
    case http
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

  public init(_ error: NetworkError) {
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
      self.init(
        kind: .http,
        statusCode: statusCode,
        headers: headers.recordedHeaders,
        bodyBase64: body.base64EncodedString()
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

  public var bodyData: Data? {
    self.bodyBase64.flatMap { Data(base64Encoded: $0) }
  }

  public var networkError: NetworkError {
    switch self.kind {
    case .invalidRequest:
      return .invalidRequest(self.message ?? "Recorded invalid request")
    case .transport:
      return .transport(URLError(.init(rawValue: self.urlErrorCode ?? NSURLErrorUnknown)))
    case .http:
      return .http(
        statusCode: self.statusCode ?? 0,
        body: self.bodyData ?? Data(),
        headers: (try? HTTPFields(recordedHeaders: self.headers)) ?? .init()
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
}

public struct RecordedHeader: Codable, Sendable, Hashable {
  public var name: String
  public var value: String

  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

public actor ReplayTransport: HTTPTransport {
  public enum Mode: Sendable {
    case matchingRequest
    case sequential
  }

  private let cassette: HTTPCassette
  private let mode: Mode
  private var remainingExchanges: [RecordedExchange]

  public init(
    cassette: HTTPCassette,
    mode: Mode = .matchingRequest
  ) {
    self.cassette = cassette
    self.mode = mode
    self.remainingExchanges = cassette.exchanges
  }

  public init(
    contentsOf url: URL,
    mode: Mode = .matchingRequest,
    decoder: JSONDecoder = HTTPCassette.jsonDecoder()
  ) throws {
    let cassette = try HTTPCassette(contentsOf: url, decoder: decoder)
    self.init(cassette: cassette, mode: mode)
  }

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

  public func remainingCount() -> Int {
    self.remainingExchanges.count
  }

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
    self.map { field in
      RecordedHeader(name: field.name.rawName, value: field.value)
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
