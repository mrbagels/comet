import Foundation

public enum NetworkEvent: Sendable {
  case requestStarted(id: UUID, method: HTTPMethod, url: URL)
  case requestCompleted(id: UUID, statusCode: Int, duration: Duration)
  case requestFailed(id: UUID, error: NetworkError, duration: Duration)
  case requestRetried(id: UUID, attempt: Int, delay: Duration)
}
