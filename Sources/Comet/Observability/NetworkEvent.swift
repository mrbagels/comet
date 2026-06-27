import Foundation

/// Activity events emitted by ``HTTPClient`` as requests start, retry, complete, or fail.
public enum NetworkEvent: Sendable {
  case requestStarted(id: UUID, method: HTTPMethod, url: URL, metadata: RequestMetadata)
  case requestCompleted(id: UUID, statusCode: Int, duration: Duration, metadata: RequestMetadata)
  case requestFailed(id: UUID, error: NetworkError, duration: Duration, metadata: RequestMetadata)
  case requestRetried(id: UUID, attempt: Int, delay: Duration, metadata: RequestMetadata)
}

extension NetworkEvent {
  /// Stable event categories for diagnostics and UI filtering.
  public enum Kind: String, Sendable, Equatable {
    case started
    case completed
    case failed
    case retried
  }

  /// The event category.
  public var kind: Kind {
    switch self {
    case .requestStarted:
      .started
    case .requestCompleted:
      .completed
    case .requestFailed:
      .failed
    case .requestRetried:
      .retried
    }
  }

  /// The request identifier shared by all events for a request.
  public var id: UUID {
    switch self {
    case .requestStarted(let id, _, _, _),
      .requestCompleted(let id, _, _, _),
      .requestFailed(let id, _, _, _),
      .requestRetried(let id, _, _, _):
      id
    }
  }

  /// Human-readable request metadata carried by the event.
  public var metadata: RequestMetadata {
    switch self {
    case .requestStarted(_, _, _, let metadata),
      .requestCompleted(_, _, _, let metadata),
      .requestFailed(_, _, _, let metadata),
      .requestRetried(_, _, _, let metadata):
      metadata
    }
  }

  /// The request display name, when metadata provides one.
  public var displayName: String? {
    self.metadata.displayName
  }

  /// The HTTP method for start events.
  public var method: HTTPMethod? {
    guard case .requestStarted(_, let method, _, _) = self else { return nil }
    return method
  }

  /// The request URL for start events.
  public var url: URL? {
    guard case .requestStarted(_, _, let url, _) = self else { return nil }
    return url
  }

  /// The HTTP status code for completed events.
  public var statusCode: Int? {
    guard case .requestCompleted(_, let statusCode, _, _) = self else { return nil }
    return statusCode
  }

  /// The request duration for completed and failed events.
  public var duration: Duration? {
    switch self {
    case .requestCompleted(_, _, let duration, _),
      .requestFailed(_, _, let duration, _):
      duration
    default:
      nil
    }
  }

  /// The transport or HTTP error for failed events.
  public var error: NetworkError? {
    guard case .requestFailed(_, let error, _, _) = self else { return nil }
    return error
  }

  /// The retry attempt number for retry events.
  public var retryAttempt: Int? {
    guard case .requestRetried(_, let attempt, _, _) = self else { return nil }
    return attempt
  }

  /// The delay before the next attempt for retry events.
  public var retryDelay: Duration? {
    guard case .requestRetried(_, _, let delay, _) = self else { return nil }
    return delay
  }

  /// A short human-readable event summary suitable for diagnostics.
  public var diagnosticSummary: String {
    let name = self.displayName.map { " \($0)" } ?? ""

    switch self {
    case .requestStarted(_, let method, let url, _):
      return "started\(name) \(method.rawValue) \(url.absoluteString)"
    case .requestCompleted(_, let statusCode, let duration, _):
      return "completed\(name) HTTP \(statusCode) in \(duration)"
    case .requestFailed(_, let error, let duration, _):
      return "failed\(name) \(error.debugSummary) in \(duration)"
    case .requestRetried(_, let attempt, let delay, _):
      return "retrying\(name) attempt \(attempt) after \(delay)"
    }
  }
}
