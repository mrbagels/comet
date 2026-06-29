import Foundation
#if canImport(Network)
import Network
#endif
import HTTPTypes
import Comet

#if canImport(Network)
/// A local HTTP listener backed by ``MockServer`` contract expectations.
///
/// Use this when a test, preview, or demo needs to exercise a real
/// ``URLSessionTransport`` instead of Comet's in-memory transport seam.
public final class LocalMockServer: @unchecked Sendable {
  public let baseURL: URL

  private let listener: NWListener
  private let core: LocalMockServerCore

  private init(
    baseURL: URL,
    listener: NWListener,
    core: LocalMockServerCore
  ) {
    self.baseURL = baseURL
    self.listener = listener
    self.core = core
  }

  deinit {
    self.stop()
  }

  /// Starts a local HTTP listener backed by strict contract expectations.
  public static func start(
    expectations: [ContractExpectation],
    latency: Duration? = nil,
    host: String = "127.0.0.1",
    port: UInt16 = 0
  ) async throws(NetworkError) -> LocalMockServer {
    try await Self.start(
      mockServer: MockServer(expectations: expectations, latency: latency),
      host: host,
      port: port
    )
  }

  /// Starts a local HTTP listener backed by cassette-derived contract expectations.
  public static func start(
    cassette: HTTPCassette,
    latency: Duration? = nil,
    host: String = "127.0.0.1",
    port: UInt16 = 0
  ) async throws(NetworkError) -> LocalMockServer {
    try await Self.start(
      mockServer: MockServer(cassette: cassette, latency: latency),
      host: host,
      port: port
    )
  }

  /// Stops accepting requests and closes open local connections.
  public func stop() {
    self.listener.cancel()
    self.core.cancelAllConnections()
  }

  /// Returns the underlying contract report.
  public func report(generatedAt: Date = Date()) async -> ContractReport {
    await self.core.report(generatedAt: generatedAt)
  }

  /// Throws when any expectations were unused or any local request violated the contract.
  public func verifyComplete() async throws(NetworkError) {
    try await self.core.verifyComplete()
  }

  /// Resets the underlying mock server contracts.
  public func reset() async {
    await self.core.reset()
  }

  private static func start(
    mockServer: MockServer,
    host: String,
    port: UInt16
  ) async throws(NetworkError) -> LocalMockServer {
    guard let listenerPort = NWEndpoint.Port(rawValue: port) else {
      throw .invalidRequest("Invalid local mock server port: \(port).")
    }

    let listener: NWListener
    do {
      listener = try NWListener(using: .tcp, on: listenerPort)
    } catch {
      throw .from(error)
    }

    let queue = DispatchQueue(label: "com.comet.local-mock-server")
    let core = LocalMockServerCore(
      mockServer: mockServer,
      host: host,
      queue: queue
    )
    listener.newConnectionHandler = { connection in
      core.accept(connection)
    }

    do {
      return try await withCheckedThrowingContinuation { continuation in
        let resolver = LocalMockServerStartResolver(continuation: continuation)

        listener.stateUpdateHandler = { state in
          switch state {
          case .ready:
            guard let resolvedPort = listener.port else {
              resolver.resume(
                throwing: NetworkError.invalidRequest("Local mock server did not publish a listening port.")
              )
              return
            }

            var components = URLComponents()
            components.scheme = "http"
            components.host = localMockServerURLHost(for: host)
            components.port = Int(resolvedPort.rawValue)

            guard let baseURL = components.url else {
              resolver.resume(
                throwing: NetworkError.invalidRequest("Unable to resolve local mock server base URL.")
              )
              return
            }

            resolver.resume(
              returning: LocalMockServer(
                baseURL: baseURL,
                listener: listener,
                core: core
              )
            )

          case .failed(let error):
            resolver.resume(
              throwing: NetworkError.invalidRequest("Local mock server failed to start: \(error).")
            )

          case .cancelled:
            resolver.resume(throwing: NetworkError.cancelled)

          default:
            break
          }
        }

        listener.start(queue: queue)
      }
    } catch {
      throw NetworkError.from(error)
    }
  }
}

private func localMockServerURLHost(for host: String) -> String {
  if host.filter({ $0 == ":" }).count > 1, !host.hasPrefix("[") {
    return "[\(host)]"
  }
  return host
}

private final class LocalMockServerStartResolver: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<LocalMockServer, any Error>?

  init(continuation: CheckedContinuation<LocalMockServer, any Error>) {
    self.continuation = continuation
  }

  func resume(returning server: LocalMockServer) {
    self.resolve { $0.resume(returning: server) }
  }

  func resume(throwing error: NetworkError) {
    self.resolve { $0.resume(throwing: error) }
  }

  private func resolve(_ body: (CheckedContinuation<LocalMockServer, any Error>) -> Void) {
    self.lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    self.lock.unlock()

    guard let continuation else { return }
    body(continuation)
  }
}

private final class LocalMockServerCore: @unchecked Sendable {
  private let mockServer: MockServer
  private let host: String
  private let queue: DispatchQueue
  private let connections = LocalMockServerConnections()

  init(
    mockServer: MockServer,
    host: String,
    queue: DispatchQueue
  ) {
    self.mockServer = mockServer
    self.host = host
    self.queue = queue
  }

  func accept(_ nwConnection: NWConnection) {
    let connection = LocalMockServerConnection(nwConnection)
    self.connections.insert(connection)

    nwConnection.stateUpdateHandler = { [connections = self.connections, connection] state in
      switch state {
      case .failed, .cancelled:
        connections.remove(connection)
      default:
        break
      }
    }

    nwConnection.start(queue: self.queue)
    self.receive(on: connection, buffer: Data())
  }

  func cancelAllConnections() {
    self.connections.cancelAll()
  }

  func report(generatedAt: Date) async -> ContractReport {
    await self.mockServer.report(generatedAt: generatedAt)
  }

  func verifyComplete() async throws(NetworkError) {
    try await self.mockServer.verifyComplete()
  }

  func reset() async {
    await self.mockServer.reset()
  }

  private func receive(
    on connection: LocalMockServerConnection,
    buffer: Data
  ) {
    connection.receive { [self] data, isComplete, error in
      if error != nil {
        self.connections.remove(connection)
        connection.cancel()
        return
      }

      var nextBuffer = buffer
      if let data {
        nextBuffer.append(data)
      }

      switch LocalHTTPRequestParser.parse(nextBuffer, host: self.host) {
      case .success(let request):
        Task {
          let response = await self.response(for: request)
          connection.send(response) { [connections = self.connections, connection] in
            connections.remove(connection)
          }
        }

      case .needMore:
        if isComplete {
          connection.cancel()
          self.connections.remove(connection)
        } else {
          self.receive(on: connection, buffer: nextBuffer)
        }

      case .failure(let error):
        let response = Self.serializedResponse(for: .invalidRequest(error))
        connection.send(response) { [connections = self.connections, connection] in
          connections.remove(connection)
        }
      }
    }
  }

  private func response(for request: LocalHTTPRequest) async -> Data {
    do {
      let response = try await self.mockServer.send(request.preparedRequest)
      return Self.serializedResponse(for: response)
    } catch {
      return Self.serializedResponse(for: NetworkError.from(error))
    }
  }

  private static func serializedResponse(for error: NetworkError) -> Data {
    switch error {
    case .http(let statusCode, let body, let headers):
      return self.serializedResponse(
        for: RawResponse(data: body, statusCode: statusCode, headers: headers)
      )
    case .invalidRequest:
      return self.serializedResponse(
        for: RawResponse(
          data: Data(error.debugSummary.utf8),
          statusCode: 400,
          headers: Self.textHeaders
        )
      )
    case .timeout:
      return self.serializedResponse(
        for: RawResponse(
          data: Data(error.debugSummary.utf8),
          statusCode: 504,
          headers: Self.textHeaders
        )
      )
    case .cancelled:
      return self.serializedResponse(
        for: RawResponse(
          data: Data(error.debugSummary.utf8),
          statusCode: 499,
          headers: Self.textHeaders
        )
      )
    default:
      return self.serializedResponse(
        for: RawResponse(
          data: Data(error.debugSummary.utf8),
          statusCode: 500,
          headers: Self.textHeaders
        )
      )
    }
  }

  private static var textHeaders: HTTPFields {
    var headers = HTTPFields()
    headers[.contentType] = "text/plain; charset=utf-8"
    return headers
  }

  private static func serializedResponse(for response: RawResponse) -> Data {
    var result = Data()
    func append(_ string: String) {
      result.append(Data(string.utf8))
    }

    append("HTTP/1.1 \(response.statusCode) \(Self.reasonPhrase(for: response.statusCode))\r\n")

    let skippedHeaders = Set(["content-length", "connection"])
    for header in response.headers {
      guard !skippedHeaders.contains(header.name.rawName.lowercased()) else { continue }
      append("\(header.name.rawName): \(header.value)\r\n")
    }

    append("Content-Length: \(response.data.count)\r\n")
    append("Connection: close\r\n")
    append("\r\n")
    result.append(response.data)
    return result
  }

  private static func reasonPhrase(for statusCode: Int) -> String {
    switch statusCode {
    case 200: "OK"
    case 201: "Created"
    case 202: "Accepted"
    case 204: "No Content"
    case 304: "Not Modified"
    case 400: "Bad Request"
    case 401: "Unauthorized"
    case 403: "Forbidden"
    case 404: "Not Found"
    case 409: "Conflict"
    case 422: "Unprocessable Content"
    case 429: "Too Many Requests"
    case 499: "Client Closed Request"
    case 500: "Internal Server Error"
    case 502: "Bad Gateway"
    case 503: "Service Unavailable"
    case 504: "Gateway Timeout"
    default: "HTTP Status"
    }
  }
}

private final class LocalMockServerConnection: @unchecked Sendable, Hashable {
  private let connection: NWConnection

  init(_ connection: NWConnection) {
    self.connection = connection
  }

  static func == (lhs: LocalMockServerConnection, rhs: LocalMockServerConnection) -> Bool {
    lhs === rhs
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  func receive(
    _ body: @escaping @Sendable (Data?, Bool, NWError?) -> Void
  ) {
    self.connection.receive(
      minimumIncompleteLength: 1,
      maximumLength: 64 * 1024
    ) { data, _, isComplete, error in
      body(data, isComplete, error)
    }
  }

  func send(
    _ data: Data,
    completion: @escaping @Sendable () -> Void
  ) {
    self.connection.send(content: data, completion: .contentProcessed { [connection = self.connection] _ in
      connection.cancel()
      completion()
    })
  }

  func cancel() {
    self.connection.cancel()
  }
}

private final class LocalMockServerConnections: @unchecked Sendable {
  private let lock = NSLock()
  private var connections = Set<LocalMockServerConnection>()

  func insert(_ connection: LocalMockServerConnection) {
    self.lock.lock()
    self.connections.insert(connection)
    self.lock.unlock()
  }

  func remove(_ connection: LocalMockServerConnection) {
    self.lock.lock()
    self.connections.remove(connection)
    self.lock.unlock()
  }

  func cancelAll() {
    self.lock.lock()
    let connections = self.connections
    self.connections.removeAll()
    self.lock.unlock()

    for connection in connections {
      connection.cancel()
    }
  }
}

private struct LocalHTTPRequest: Sendable {
  var preparedRequest: PreparedRequest
}

private enum LocalHTTPRequestParser {
  enum Result {
    case success(LocalHTTPRequest)
    case needMore
    case failure(String)
  }

  private static let hostHeaderName = HTTPField.Name("Host")!

  static func parse(_ data: Data, host: String) -> Result {
    let separator = Data("\r\n\r\n".utf8)
    guard let headerRange = data.range(of: separator) else {
      return .needMore
    }

    guard let headerText = String(
      data: Data(data[..<headerRange.lowerBound]),
      encoding: .isoLatin1
    ) else {
      return .failure("Unable to decode HTTP request headers.")
    }

    var lines = headerText.components(separatedBy: "\r\n")
    guard !lines.isEmpty else {
      return .failure("HTTP request did not contain a request line.")
    }

    let requestLine = lines.removeFirst()
    let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard requestParts.count == 3 else {
      return .failure("HTTP request line was malformed.")
    }

    let method = HTTPMethod(rawValue: requestParts[0])
    let target = requestParts[1]

    var headers = HTTPFields()
    var contentLength = 0
    for line in lines where !line.isEmpty {
      let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else {
        return .failure("HTTP header was malformed: \(line).")
      }

      let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
      let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
      if name.caseInsensitiveCompare("Content-Length") == .orderedSame {
        contentLength = Int(value) ?? -1
      }
      if let fieldName = HTTPField.Name(name) {
        headers[fieldName] = value
      }
    }

    guard contentLength >= 0 else {
      return .failure("HTTP Content-Length header was invalid.")
    }

    let bodyStart = headerRange.upperBound
    guard data.count >= bodyStart + contentLength else {
      return .needMore
    }

    let body = contentLength == 0
      ? nil
      : Data(data[bodyStart..<bodyStart + contentLength])

    guard let url = Self.url(for: target, host: host, headers: headers) else {
      return .failure("HTTP request target was invalid: \(target).")
    }

    return .success(
      LocalHTTPRequest(
        preparedRequest: PreparedRequest(
          url: url,
          method: method,
          headers: headers,
          body: body,
          timeout: .seconds(30)
        )
      )
    )
  }

  private static func url(
    for target: String,
    host: String,
    headers: HTTPFields
  ) -> URL? {
    if let absoluteURL = URL(string: target), absoluteURL.scheme != nil {
      return absoluteURL
    }

    let normalizedTarget = target.hasPrefix("/") ? target : "/\(target)"
    guard var components = URLComponents(string: normalizedTarget) else {
      return nil
    }

    components.scheme = "http"
    components.host = localMockServerURLHost(for: host)

    if let port = Self.port(fromHostHeader: headers[Self.hostHeaderName]) {
      components.port = port
    }

    return components.url
  }

  private static func port(fromHostHeader hostHeader: String?) -> Int? {
    guard let hostHeader, !hostHeader.isEmpty else { return nil }

    if hostHeader.hasPrefix("[") {
      guard let closingBracket = hostHeader.firstIndex(of: "]") else { return nil }
      let suffix = hostHeader[hostHeader.index(after: closingBracket)...]
      guard suffix.first == ":" else { return nil }
      return Int(suffix.dropFirst())
    }

    guard hostHeader.filter({ $0 == ":" }).count == 1,
          let separator = hostHeader.firstIndex(of: ":")
    else {
      return nil
    }
    return Int(hostHeader[hostHeader.index(after: separator)...])
  }
}
#else
@available(
  *,
  unavailable,
  message: "LocalMockServer requires Network.framework. Use MockServer as an in-memory HTTPTransport on this platform."
)
public final class LocalMockServer: @unchecked Sendable {}
#endif
