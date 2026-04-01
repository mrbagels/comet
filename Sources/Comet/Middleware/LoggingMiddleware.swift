import Foundation
import HTTPTypes

public struct LoggingMiddleware: Middleware {
  public enum LogLevel: Sendable {
    case request
    case response
    case verbose
  }

  public var isEnabled: Bool
  public var redactedHeaders: Set<String>
  public var logLevel: LogLevel
  public var logger: @Sendable (String) -> Void

  public init(
    isEnabled: Bool = true,
    redactedHeaders: Set<String> = ["authorization", "cookie", "set-cookie"],
    logLevel: LogLevel = .response,
    logger: @escaping @Sendable (String) -> Void = { message in
      fputs(message + "\n", stderr)
    }
  ) {
    self.isEnabled = isEnabled
    self.redactedHeaders = redactedHeaders
    self.logLevel = logLevel
    self.logger = logger
  }

  public func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest {
    guard self.isEnabled else { return request }

    switch self.logLevel {
    case .request, .verbose:
      let headerSummary = request.headers.redactedDescription(redactedHeaders: self.redactedHeaders)
      let bodySize = request.body?.count ?? 0
      self.logger("[Comet][\(context.requestID)] → \(request.method.rawValue) \(request.url.absoluteString) headers=\(headerSummary) body=\(bodySize)b")
      if self.logLevel == .verbose {
        self.logger(request.curlCommand(redactedHeaders: self.redactedHeaders))
      }
    case .response:
      break
    }

    return request
  }

  public func process(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareResult {
    guard self.isEnabled else { return .proceed(result) }

    switch self.logLevel {
    case .response, .verbose:
      switch result {
      case .success(let response):
        self.logger("[Comet][\(context.requestID)] ← \(response.statusCode) \(request.url.absoluteString) body=\(response.data.count)b")
      case .failure(let error):
        self.logger("[Comet][\(context.requestID)] ← error \(error) \(request.url.absoluteString)")
      }
    case .request:
      break
    }

    return .proceed(result)
  }
}
