import Foundation

/// A completed request trace emitted by ``HTTPClient`` after transport execution finishes.
public struct RequestTrace: Identifiable, Sendable {
  public let id: UUID
  public let metadata: RequestMetadata
  public let method: HTTPMethod
  public let url: URL
  public let attempts: [RequestTraceAttempt]
  public let duration: Duration
  public let result: RequestTraceResult
  public let traceContext: TraceContext?
  public let cacheEvents: [RequestCacheTraceEvent]

  public init(
    id: UUID,
    metadata: RequestMetadata,
    method: HTTPMethod,
    url: URL,
    attempts: [RequestTraceAttempt],
    duration: Duration,
    result: RequestTraceResult
  ) {
    self.id = id
    self.metadata = metadata
    self.method = method
    self.url = url
    self.attempts = attempts
    self.duration = duration
    self.result = result
    self.traceContext = nil
    self.cacheEvents = []
  }

  public init(
    id: UUID,
    metadata: RequestMetadata,
    method: HTTPMethod,
    url: URL,
    attempts: [RequestTraceAttempt],
    duration: Duration,
    result: RequestTraceResult,
    traceContext: TraceContext?
  ) {
    self.init(
      id: id,
      metadata: metadata,
      method: method,
      url: url,
      attempts: attempts,
      duration: duration,
      result: result,
      traceContext: traceContext,
      cacheEvents: []
    )
  }

  public init(
    id: UUID,
    metadata: RequestMetadata,
    method: HTTPMethod,
    url: URL,
    attempts: [RequestTraceAttempt],
    duration: Duration,
    result: RequestTraceResult,
    traceContext: TraceContext?,
    cacheEvents: [RequestCacheTraceEvent]
  ) {
    self.id = id
    self.metadata = metadata
    self.method = method
    self.url = url
    self.attempts = attempts
    self.duration = duration
    self.result = result
    self.traceContext = traceContext
    self.cacheEvents = cacheEvents
  }

  /// Number of bytes in the first prepared request body.
  public var requestBytes: Int {
    self.attempts.first?.requestBytes ?? 0
  }

  /// Number of response bytes returned by the final successful transport attempt.
  public var responseBytes: Int {
    guard case .success(_, let responseBytes) = self.result else { return 0 }
    return responseBytes
  }

  /// The final HTTP status code, when the request reached a server response.
  public var statusCode: Int? {
    guard case .success(let statusCode, _) = self.result else { return nil }
    return statusCode
  }

  /// The final transport or middleware failure, when the request failed before a response.
  public var error: NetworkError? {
    guard case .failure(let error) = self.result else { return nil }
    return error
  }

  /// The distributed trace ID propagated with this request, when available.
  public var traceID: String? {
    self.traceContext?.traceID ?? self.metadata.traceID
  }

  /// A concise trace summary for logs and debug UI.
  public var diagnosticSummary: String {
    let name = self.metadata.displayName.map { " \($0)" } ?? ""
    let traceID = self.traceID.map { " traceID=\($0)" } ?? ""
    switch self.result {
    case .success(let statusCode, let responseBytes):
      return "trace\(name)\(traceID) \(self.method.rawValue) \(self.url.absoluteString) -> HTTP \(statusCode), \(responseBytes) bytes, \(self.attempts.count) attempt(s)"
    case .failure(let error):
      return "trace\(name)\(traceID) \(self.method.rawValue) \(self.url.absoluteString) -> \(error.debugSummary), \(self.attempts.count) attempt(s)"
    }
  }
}

/// A single transport attempt inside a ``RequestTrace``.
public struct RequestTraceAttempt: Identifiable, Sendable {
  public let id: UUID
  public let number: Int
  public let method: HTTPMethod
  public let url: URL
  public let requestBytes: Int
  public let responseStatusCode: Int?
  public let responseBytes: Int?
  public let error: NetworkError?
  public let duration: Duration
  public var retryDelay: Duration?

  public init(
    id: UUID = UUID(),
    number: Int,
    method: HTTPMethod,
    url: URL,
    requestBytes: Int,
    responseStatusCode: Int?,
    responseBytes: Int?,
    error: NetworkError?,
    duration: Duration,
    retryDelay: Duration? = nil
  ) {
    self.id = id
    self.number = number
    self.method = method
    self.url = url
    self.requestBytes = requestBytes
    self.responseStatusCode = responseStatusCode
    self.responseBytes = responseBytes
    self.error = error
    self.duration = duration
    self.retryDelay = retryDelay
  }
}

/// The final transport-level outcome for a ``RequestTrace``.
public enum RequestTraceResult: Sendable {
  case success(statusCode: Int, responseBytes: Int)
  case failure(NetworkError)
}
