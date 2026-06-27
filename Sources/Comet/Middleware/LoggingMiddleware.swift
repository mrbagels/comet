import Foundation
import HTTPTypes

/// Emits human-readable request and response logs, with optional cURL output in verbose mode.
public struct LoggingMiddleware: Middleware {
  /// Controls which phases of the request lifecycle get logged.
  public enum LogLevel: Sendable {
    case request
    case response
    case verbose
  }

  public var isEnabled: Bool
  public var redactionPolicy: RedactionPolicy?
  public var logLevel: LogLevel
  public var curlCommandOptions: CURLCommandOptions
  public var logger: @Sendable (String) -> Void

  /// Creates a logging middleware with redaction and output controls.
  public init(
    isEnabled: Bool = true,
    redactedHeaders: Set<String>? = nil,
    redactionPolicy: RedactionPolicy? = nil,
    logLevel: LogLevel = .response,
    curlCommandOptions: CURLCommandOptions = .init(),
    logger: @escaping @Sendable (String) -> Void = { message in
      fputs(message + "\n", stderr)
    }
  ) {
    self.isEnabled = isEnabled
    self.redactionPolicy = redactionPolicy ?? redactedHeaders.map { RedactionPolicy(redactedHeaders: $0) }
    self.logLevel = logLevel
    self.curlCommandOptions = curlCommandOptions
    self.logger = logger
  }

  /// Logs the outgoing request before transport execution when enabled.
  public func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest {
    guard self.isEnabled else { return request }

    switch self.logLevel {
    case .request, .verbose:
      let redactionPolicy = self.redactionPolicy ?? request.redactionPolicy
      let headerSummary = request.headers.redactedDescription(redactionPolicy: redactionPolicy)
      let body = redactionPolicy.recordedRequestBody(for: request)
      let bodySize = body.data?.count ?? 0
      let name = request.metadata.displayName.map { " \($0)" } ?? ""
      self.logger("[Comet][\(context.requestID)]\(name) → \(request.method.rawValue) \(request.url.absoluteString) headers=\(headerSummary) body=\(bodySize)b")
      if self.logLevel == .verbose {
        self.logger(request.curlCommand(
          redactionPolicy: redactionPolicy,
          options: self.curlCommandOptions
        ))
      }
    case .response:
      break
    }

    return request
  }

  /// Logs the incoming response or failure after transport execution when enabled.
  public func process(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareResult {
    guard self.isEnabled else { return .proceed(result) }

    switch self.logLevel {
    case .response, .verbose:
      let name = request.metadata.displayName.map { " \($0)" } ?? ""
      switch result {
      case .success(let response):
        self.logger("[Comet][\(context.requestID)]\(name) ← \(response.statusCode) \(request.url.absoluteString) body=\(response.data.count)b")
      case .failure(let error):
        self.logger("[Comet][\(context.requestID)]\(name) ← error \(error) \(request.url.absoluteString)")
      }
    case .request:
      break
    }

    return .proceed(result)
  }
}
