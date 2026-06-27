import Foundation

/// Activity events emitted by ``HTTPClient`` as requests start, retry, complete, or fail.
public enum NetworkEvent: Sendable {
  case requestStarted(id: UUID, method: HTTPMethod, url: URL, metadata: RequestMetadata)
  case requestCompleted(id: UUID, statusCode: Int, duration: Duration, metadata: RequestMetadata)
  case requestFailed(id: UUID, error: NetworkError, duration: Duration, metadata: RequestMetadata)
  case requestRetried(id: UUID, attempt: Int, delay: Duration, metadata: RequestMetadata)
}
