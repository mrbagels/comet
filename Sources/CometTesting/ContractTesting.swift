import Foundation
import HTTPTypes
import Comet

/// Matches a request, response, header, query item, or metadata value in a contract expectation.
public enum ContractValueExpectation: Sendable, Hashable {
  case any
  case exact(String)

  public func matches(_ value: String?) -> Bool {
    switch self {
    case .any:
      return value != nil
    case .exact(let expected):
      return value == expected
    }
  }

  var reportValue: String {
    switch self {
    case .any:
      return "<any>"
    case .exact(let value):
      return value
    }
  }
}

/// Matches a request body in a contract expectation.
public enum ContractBodyExpectation: Sendable, Hashable {
  case any
  case absent
  case exact(Data)

  public func matches(_ body: Data?) -> Bool {
    switch self {
    case .any:
      return true
    case .absent:
      return body == nil
    case .exact(let expected):
      return body == expected
    }
  }

  var reportValue: String {
    switch self {
    case .any:
      return "<any>"
    case .absent:
      return "<absent>"
    case .exact(let data):
      return data.base64EncodedString()
    }
  }
}

/// Describes an expected query item.
public struct ContractQueryExpectation: Sendable, Hashable {
  public var name: String
  public var value: ContractValueExpectation

  public init(
    name: String,
    value: ContractValueExpectation = .any
  ) {
    self.name = name
    self.value = value
  }
}

/// Describes an expected header.
public struct ContractHeaderExpectation: Sendable, Hashable {
  public var name: String
  public var value: ContractValueExpectation

  public init(
    name: String,
    value: ContractValueExpectation = .any
  ) {
    self.name = name
    self.value = value
  }
}

/// Describes expected request metadata.
public struct ContractMetadataExpectation: Sendable, Hashable {
  public var name: ContractValueExpectation?
  public var operationID: ContractValueExpectation?
  public var tags: Set<String>

  public init(
    name: ContractValueExpectation? = nil,
    operationID: ContractValueExpectation? = nil,
    tags: Set<String> = []
  ) {
    self.name = name
    self.operationID = operationID
    self.tags = tags
  }

  public static let any = Self()
}

/// The response or failure produced when a contract expectation matches.
public enum ContractOutcome: Sendable {
  case response(RawResponse)
  case failure(NetworkError)

  func replay() throws(NetworkError) -> RawResponse {
    switch self {
    case .response(let response):
      return response
    case .failure(let error):
      throw error
    }
  }
}

/// A strict request contract plus the outcome to return when the request matches.
public struct ContractExpectation: Sendable {
  public var id: String
  public var method: HTTPMethod?
  public var path: String?
  public var query: [ContractQueryExpectation]
  public var headers: [ContractHeaderExpectation]
  public var body: ContractBodyExpectation
  public var metadata: ContractMetadataExpectation
  public var outcome: ContractOutcome

  public init(
    id: String,
    method: HTTPMethod? = nil,
    path: String? = nil,
    query: [ContractQueryExpectation] = [],
    headers: [ContractHeaderExpectation] = [],
    body: ContractBodyExpectation = .any,
    metadata: ContractMetadataExpectation = .any,
    outcome: ContractOutcome
  ) {
    self.id = id
    self.method = method
    self.path = path
    self.query = query
    self.headers = headers
    self.body = body
    self.metadata = metadata
    self.outcome = outcome
  }

  /// Creates a contract from an already prepared request.
  public init(
    id: String,
    preparedRequest request: PreparedRequest,
    response: RawResponse
  ) {
    self.init(
      id: id,
      method: request.method,
      path: request.url.path,
      query: URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .map { ContractQueryExpectation(name: $0.name, value: .exact($0.value ?? "")) } ?? [],
      headers: request.headers.map {
        ContractHeaderExpectation(name: $0.name.rawName, value: .exact($0.value))
      },
      body: request.body.map(ContractBodyExpectation.exact) ?? .absent,
      metadata: ContractMetadataExpectation(
        name: request.metadata.name.map(ContractValueExpectation.exact),
        operationID: request.metadata.operationID.map(ContractValueExpectation.exact),
        tags: Set(request.metadata.tags)
      ),
      outcome: .response(response)
    )
  }

  /// Creates a contract from a typed request using the provided client configuration.
  public init<R: APIRequest>(
    id: String,
    request: R,
    client: HTTPClient,
    response: RawResponse
  ) throws(NetworkError) {
    self.init(
      id: id,
      preparedRequest: try client.prepare(request),
      response: response
    )
  }

  /// Converts a recorded cassette exchange into a strict contract expectation.
  public init(
    id: String,
    exchange: RecordedExchange
  ) throws(NetworkError) {
    let request = try exchange.request.makePreparedRequest()
    self.init(
      id: id,
      method: request.method,
      path: request.url.path,
      query: URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .map { ContractQueryExpectation(name: $0.name, value: .exact($0.value ?? "")) } ?? [],
      headers: exchange.request.headers.map {
        ContractHeaderExpectation(
          name: $0.name,
          value: $0.value == "<redacted>" ? .any : .exact($0.value)
        )
      },
      body: exchange.request.bodyWasRedacted
        ? .any
        : exchange.request.bodyData.map(ContractBodyExpectation.exact) ?? .absent,
      outcome: try ContractOutcome(exchange.outcome)
    )
  }

  func evaluate(_ request: PreparedRequest) -> [ContractDifference] {
    var differences: [ContractDifference] = []

    if let method, method != request.method {
      differences.append(
        ContractDifference(
          field: "method",
          expected: method.rawValue,
          actual: request.method.rawValue
        )
      )
    }

    if let path, path != request.url.path {
      differences.append(
        ContractDifference(
          field: "path",
          expected: path,
          actual: request.url.path
        )
      )
    }

    let queryItems = request.queryValues
    for expectation in self.query {
      let actual = queryItems[expectation.name]?.first
      guard expectation.value.matches(actual) else {
        differences.append(
          ContractDifference(
            field: "query.\(expectation.name)",
            expected: expectation.value.reportValue,
            actual: actual ?? "<missing>"
          )
        )
        continue
      }
    }

    for expectation in self.headers {
      let actual = request.headerValue(named: expectation.name)
      guard expectation.value.matches(actual) else {
        differences.append(
          ContractDifference(
            field: "header.\(expectation.name)",
            expected: expectation.value.reportValue,
            actual: actual ?? "<missing>"
          )
        )
        continue
      }
    }

    if !self.body.matches(request.body) {
      differences.append(
        ContractDifference(
          field: "body",
          expected: self.body.reportValue,
          actual: request.body?.base64EncodedString() ?? "<absent>"
        )
      )
    }

    if let name = self.metadata.name, !name.matches(request.metadata.name) {
      differences.append(
        ContractDifference(
          field: "metadata.name",
          expected: name.reportValue,
          actual: request.metadata.name ?? "<missing>"
        )
      )
    }

    if let operationID = self.metadata.operationID, !operationID.matches(request.metadata.operationID) {
      differences.append(
        ContractDifference(
          field: "metadata.operationID",
          expected: operationID.reportValue,
          actual: request.metadata.operationID ?? "<missing>"
        )
      )
    }

    let requestTags = Set(request.metadata.tags)
    let missingTags = self.metadata.tags.subtracting(requestTags)
    if !missingTags.isEmpty {
      differences.append(
        ContractDifference(
          field: "metadata.tags",
          expected: self.metadata.tags.sorted().joined(separator: ","),
          actual: requestTags.sorted().joined(separator: ",")
        )
      )
    }

    return differences
  }
}

public extension HTTPCassette {
  /// Converts recorded cassette exchanges into strict contract expectations.
  func contractExpectations(
    idPrefix: String = "cassette"
  ) throws(NetworkError) -> [ContractExpectation] {
    var expectations: [ContractExpectation] = []
    expectations.reserveCapacity(self.exchanges.count)
    for (index, exchange) in self.exchanges.enumerated() {
      expectations.append(
        try ContractExpectation(id: "\(idPrefix)-\(index + 1)", exchange: exchange)
      )
    }
    return expectations
  }
}

/// A single matched contract expectation.
public struct ContractMatch: Codable, Sendable, Hashable {
  public var expectationID: String
  public var request: ContractRequestSnapshot

  public init(expectationID: String, request: ContractRequestSnapshot) {
    self.expectationID = expectationID
    self.request = request
  }
}

/// A mismatch between expected and actual request state.
public struct ContractDifference: Codable, Sendable, Hashable {
  public var field: String
  public var expected: String
  public var actual: String

  public init(field: String, expected: String, actual: String) {
    self.field = field
    self.expected = expected
    self.actual = actual
  }
}

/// A request snapshot suitable for contract reports.
public struct ContractRequestSnapshot: Codable, Sendable, Hashable {
  public var request: RecordedRequest
  public var metadataName: String?
  public var metadataOperationID: String?
  public var metadataTags: [String]

  public init(_ request: PreparedRequest) {
    self.request = RecordedRequest(request, redaction: request.redactionPolicy)
    self.metadataName = request.metadata.name
    self.metadataOperationID = request.metadata.operationID
    self.metadataTags = request.metadata.tags
  }
}

/// A contract validation failure.
public struct ContractViolation: Codable, Sendable, Hashable {
  public enum Kind: String, Codable, Sendable, Hashable {
    case mismatch
    case unexpectedRequest
    case unusedExpectation
  }

  public var kind: Kind
  public var expectationID: String?
  public var request: ContractRequestSnapshot?
  public var message: String
  public var differences: [ContractDifference]

  public init(
    kind: Kind,
    expectationID: String? = nil,
    request: ContractRequestSnapshot? = nil,
    message: String,
    differences: [ContractDifference] = []
  ) {
    self.kind = kind
    self.expectationID = expectationID
    self.request = request
    self.message = message
    self.differences = differences
  }
}

/// A JSON-exportable report of contract matches and violations.
public struct ContractReport: Codable, Sendable, Hashable {
  public var generatedAt: Date
  public var matches: [ContractMatch]
  public var violations: [ContractViolation]

  public init(
    generatedAt: Date = Date(),
    matches: [ContractMatch] = [],
    violations: [ContractViolation] = []
  ) {
    self.generatedAt = generatedAt
    self.matches = matches
    self.violations = violations
  }

  public var passed: Bool {
    self.violations.isEmpty
  }

  /// Encodes the report as JSON data for CI artifacts.
  public func encoded(prettyPrinted: Bool = true) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if prettyPrinted {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    return try encoder.encode(self)
  }

  /// Writes the report to disk as JSON.
  public func write(
    to url: URL,
    prettyPrinted: Bool = true
  ) throws {
    try self.encoded(prettyPrinted: prettyPrinted).write(to: url, options: .atomic)
  }
}

/// Validates prepared requests against strict expectations before returning fixture outcomes.
public actor ContractTransport: HTTPTransport {
  private let initialExpectations: [ContractExpectation]
  private var remainingExpectations: [ContractExpectation]
  private var matches: [ContractMatch] = []
  private var violations: [ContractViolation] = []

  public init(expectations: [ContractExpectation]) {
    self.initialExpectations = expectations
    self.remainingExpectations = expectations
  }

  public init(cassette: HTTPCassette) throws(NetworkError) {
    let expectations = try cassette.contractExpectations()
    self.initialExpectations = expectations
    self.remainingExpectations = expectations
  }

  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    for index in self.remainingExpectations.indices {
      let expectation = self.remainingExpectations[index]
      let differences = expectation.evaluate(request)
      guard differences.isEmpty else { continue }

      self.remainingExpectations.remove(at: index)
      self.matches.append(
        ContractMatch(
          expectationID: expectation.id,
          request: ContractRequestSnapshot(request)
        )
      )
      return try expectation.outcome.replay()
    }

    let violation = self.violation(for: request)
    self.violations.append(violation)
    throw .invalidRequest(violation.message)
  }

  /// Returns a report with matches, violations, and currently unused expectations.
  public func report(generatedAt: Date = Date()) -> ContractReport {
    ContractReport(
      generatedAt: generatedAt,
      matches: self.matches,
      violations: self.violations + self.unusedExpectationViolations()
    )
  }

  /// Throws when any expectations have not been consumed or any request violated the contract.
  public func verifyComplete() throws(NetworkError) {
    let report = self.report()
    guard report.passed else {
      let summary = report.violations
        .map(\.message)
        .joined(separator: "\n")
      throw .invalidRequest(summary)
    }
  }

  /// Restores the transport to its initial expectation list.
  public func reset() {
    self.remainingExpectations = self.initialExpectations
    self.matches = []
    self.violations = []
  }

  private func violation(for request: PreparedRequest) -> ContractViolation {
    let snapshot = ContractRequestSnapshot(request)
    guard let nearest = self.remainingExpectations.first else {
      return ContractViolation(
        kind: .unexpectedRequest,
        request: snapshot,
        message: "Unexpected request \(request.method.rawValue) \(request.url.absoluteString)."
      )
    }

    let differences = nearest.evaluate(request)
    return ContractViolation(
      kind: differences.isEmpty ? .unexpectedRequest : .mismatch,
      expectationID: nearest.id,
      request: snapshot,
      message: "Request did not satisfy contract expectation \(nearest.id).",
      differences: differences
    )
  }

  private func unusedExpectationViolations() -> [ContractViolation] {
    self.remainingExpectations.map { expectation in
      ContractViolation(
        kind: .unusedExpectation,
        expectationID: expectation.id,
        message: "Contract expectation \(expectation.id) was not used."
      )
    }
  }
}

/// A higher-level facade for deterministic mock scenarios backed by contract expectations.
public actor MockServer: HTTPTransport {
  private let latency: Duration?
  private let transport: ContractTransport

  public init(
    expectations: [ContractExpectation],
    latency: Duration? = nil
  ) {
    self.latency = latency
    self.transport = ContractTransport(expectations: expectations)
  }

  public init(
    cassette: HTTPCassette,
    latency: Duration? = nil
  ) throws(NetworkError) {
    self.latency = latency
    self.transport = ContractTransport(expectations: try cassette.contractExpectations())
  }

  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    if let latency {
      do {
        try await Task.sleep(for: latency)
      } catch {
        throw NetworkError.from(error)
      }
    }
    return try await self.transport.send(request)
  }

  public func report(generatedAt: Date = Date()) async -> ContractReport {
    await self.transport.report(generatedAt: generatedAt)
  }

  public func verifyComplete() async throws(NetworkError) {
    try await self.transport.verifyComplete()
  }

  public func reset() async {
    await self.transport.reset()
  }
}

private extension ContractOutcome {
  init(_ outcome: RecordedExchange.Outcome) throws(NetworkError) {
    switch outcome {
    case .success(let response):
      self = .response(try response.makeRawResponse())
    case .failure(let error):
      self = .failure(try error.makeNetworkError())
    }
  }
}

private extension PreparedRequest {
  var queryValues: [String: [String]] {
    let items = URLComponents(url: self.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    var values: [String: [String]] = [:]
    for item in items {
      values[item.name, default: []].append(item.value ?? "")
    }
    return values
  }

  func headerValue(named name: String) -> String? {
    guard let fieldName = HTTPField.Name(name) else { return nil }
    return self.headers[fieldName]
  }
}
