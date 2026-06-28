import Foundation

/// Injects W3C trace propagation headers into outgoing requests.
public struct TracePropagationMiddleware: Middleware {
  public var replacesExistingHeader: Bool

  private let makeTraceContext: @Sendable (MiddlewareContext) -> TraceContext

  /// Creates middleware that writes a `traceparent` header from request metadata or the current request ID.
  public init(
    replacesExistingHeader: Bool = false,
    makeTraceContext: @escaping @Sendable (MiddlewareContext) -> TraceContext = {
      TraceContext.generated(requestID: $0.requestID)
    }
  ) {
    self.replacesExistingHeader = replacesExistingHeader
    self.makeTraceContext = makeTraceContext
  }

  public func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest {
    if !self.replacesExistingHeader, request.headers[TraceContext.traceparentHeaderName] != nil {
      return request
    }

    let traceContext = request.metadata.traceContext ?? self.makeTraceContext(context)
    var headers = request.headers
    headers[TraceContext.traceparentHeaderName] = traceContext.traceparent

    return PreparedRequest(
      url: request.url,
      method: request.method,
      headers: headers,
      body: request.body,
      timeout: request.timeout,
      metadata: request.metadata,
      redactionPolicy: request.redactionPolicy,
      retryPolicy: request.retryPolicy
    )
  }
}
