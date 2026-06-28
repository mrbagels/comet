import Foundation
import HTTPTypes

/// Response metadata emitted before streamed response bytes.
public struct HTTPStreamResponse: Sendable {
  public let statusCode: Int
  public let headers: HTTPFields

  public init(
    statusCode: Int,
    headers: HTTPFields = .init()
  ) {
    self.statusCode = statusCode
    self.headers = headers
  }
}

/// Events emitted by a streaming HTTP response.
public enum HTTPStreamEvent: Sendable {
  case response(HTTPStreamResponse)
  case bytes(Data)
  case complete
}

/// A parsed Server-Sent Events frame.
public struct ServerSentEvent: Sendable, Equatable {
  public let event: String?
  public let id: String?
  public let data: String
  public let retryMilliseconds: Int?

  public init(
    event: String? = nil,
    id: String? = nil,
    data: String,
    retryMilliseconds: Int? = nil
  ) {
    self.event = event
    self.id = id
    self.data = data
    self.retryMilliseconds = retryMilliseconds
  }
}

/// Identifies upload or download progress.
public enum TransferProgressKind: Sendable, Equatable {
  case upload
  case download
}

/// A progress update for HTTP transfers.
public struct TransferProgress: Sendable, Equatable {
  public let kind: TransferProgressKind
  public let completedBytes: Int64
  public let totalBytes: Int64?

  public init(
    kind: TransferProgressKind,
    completedBytes: Int64,
    totalBytes: Int64? = nil
  ) {
    self.kind = kind
    self.completedBytes = completedBytes
    self.totalBytes = totalBytes
  }

  /// Returns a completed fraction when the total byte count is known and non-zero.
  public var fractionCompleted: Double? {
    guard let totalBytes, totalBytes > 0 else { return nil }
    return Double(self.completedBytes) / Double(totalBytes)
  }
}
