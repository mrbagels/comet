import Foundation
import HTTPTypes

public enum NetworkError: Error, Sendable {
  case invalidRequest(String)
  case transport(URLError)
  case http(statusCode: Int, body: Data, headers: HTTPFields)
  case decoding(DecodingError)
  case encoding(String)
  case middleware(String)
  case cancelled
  case timeout
  case unknown(any Error & Sendable)
}

public extension NetworkError {
  static func from(_ error: any Error) -> Self {
    if let networkError = error as? Self {
      return networkError
    }
    if error is CancellationError {
      return .cancelled
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .cancelled:
        return .cancelled
      case .timedOut:
        return .timeout
      default:
        return .transport(urlError)
      }
    }
    if let decodingError = error as? DecodingError {
      return .decoding(decodingError)
    }
    return .unknown(AnySendableError(description: String(describing: error)))
  }
}

private struct AnySendableError: Error, Sendable {
  let description: String
}
