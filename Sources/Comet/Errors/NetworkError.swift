import Foundation
import HTTPTypes

/// The typed error surface used throughout Comet.
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

extension NetworkError: LocalizedError, CustomStringConvertible {
  /// The HTTP status code for an unsuccessful HTTP response, when available.
  public var statusCode: Int? {
    guard case .http(let statusCode, _, _) = self else { return nil }
    return statusCode
  }

  /// The raw HTTP response body for an unsuccessful HTTP response, when available.
  public var bodyData: Data? {
    guard case .http(_, let body, _) = self else { return nil }
    return body
  }

  /// The HTTP response headers for an unsuccessful HTTP response, when available.
  public var responseHeaders: HTTPFields? {
    guard case .http(_, _, let headers) = self else { return nil }
    return headers
  }

  /// A best-effort text representation of the recorded response body.
  public var bodyString: String? {
    guard let bodyData else { return nil }
    let encoding = self.responseHeaders?.suggestedTextEncoding ?? .utf8
    return String(data: bodyData, encoding: encoding)
      ?? String(data: bodyData, encoding: .utf8)
  }

  /// A pretty-printed JSON representation of the recorded response body, when it contains valid JSON.
  public var prettyBodyJSONString: String? {
    guard let bodyData else { return nil }

    do {
      let object = try JSONSerialization.jsonObject(with: bodyData)
      let prettyData = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
      )
      return String(decoding: prettyData, as: UTF8.self)
    } catch {
      return nil
    }
  }

  /// Indicates whether the error represents a likely connectivity failure.
  public var isConnectivityError: Bool {
    guard case .transport(let urlError) = self else { return false }
    return [
      URLError.notConnectedToInternet,
      .networkConnectionLost,
      .cannotConnectToHost,
      .cannotFindHost,
      .dnsLookupFailed
    ].contains(urlError.code)
  }

  /// Indicates whether the request was cancelled.
  public var isCancellationError: Bool {
    if case .cancelled = self { return true }
    return false
  }

  /// Indicates whether the error represents a timeout.
  public var isTimeoutError: Bool {
    switch self {
    case .timeout:
      true
    case .transport(let urlError):
      urlError.code == .timedOut
    default:
      false
    }
  }

  /// Returns a concise, developer-facing summary suitable for logs and debug UI.
  public var debugSummary: String {
    switch self {
    case .invalidRequest(let message):
      return "Invalid request: \(message)"
    case .transport(let urlError):
      return "Transport error (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
    case .http(let statusCode, _, _):
      if let prettyBodyJSONString {
        return "HTTP \(statusCode)\n\(prettyBodyJSONString)"
      }
      if let bodyString, !bodyString.isEmpty {
        return "HTTP \(statusCode)\n\(bodyString)"
      }
      return "HTTP \(statusCode)"
    case .decoding(let error):
      return "Decoding error: \(error)"
    case .encoding(let message):
      return "Encoding error: \(message)"
    case .middleware(let message):
      return "Middleware error: \(message)"
    case .cancelled:
      return "Request cancelled"
    case .timeout:
      return "Request timed out"
    case .unknown(let error):
      return "Unknown error: \(error)"
    }
  }

  public var errorDescription: String? {
    self.debugSummary
  }

  public var description: String {
    self.debugSummary
  }
}

public extension NetworkError {
  /// Normalizes arbitrary thrown errors into ``NetworkError``.
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
