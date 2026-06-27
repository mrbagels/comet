import Foundation
import HTTPTypes

/// Controls whether a prepared request is eligible for retry after a retryable response or transport error.
public enum RequestRetryPolicy: Sendable, Equatable {
  /// Retry safe HTTP methods and requests carrying an `Idempotency-Key` header.
  case automatic
  /// Retry safe and idempotent HTTP methods, plus requests carrying an `Idempotency-Key` header.
  case idempotentMethods
  /// Retry whenever ``RetryMiddleware`` sees a retryable response or transport error.
  case always
  /// Never retry this request.
  case never

  public func allowsRetry(for request: PreparedRequest) -> Bool {
    switch self {
    case .automatic:
      return request.method.isHTTPSafe || request.hasIdempotencyKey
    case .idempotentMethods:
      return request.method.isHTTPIdempotent || request.hasIdempotencyKey
    case .always:
      return true
    case .never:
      return false
    }
  }
}

private extension PreparedRequest {
  var hasIdempotencyKey: Bool {
    guard let header = HTTPField.Name("Idempotency-Key") else { return false }
    return self.headers[header] != nil
  }
}

private extension HTTPMethod {
  var isHTTPSafe: Bool {
    ["GET", "HEAD", "OPTIONS", "TRACE"].contains(self.rawValue)
  }

  var isHTTPIdempotent: Bool {
    self.isHTTPSafe || ["PUT", "DELETE"].contains(self.rawValue)
  }
}
