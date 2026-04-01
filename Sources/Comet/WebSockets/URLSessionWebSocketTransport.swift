import Foundation

/// A WebSocket transport backed by ``Foundation/URLSessionWebSocketTask``.
public struct URLSessionWebSocketTransport: WebSocketTransport, Sendable {
  private let configuration: URLSessionConfiguration

  /// Creates a URLSession-backed WebSocket transport.
  public init(configuration: URLSessionConfiguration = .default) {
    self.configuration = configuration
  }

  /// Connects a WebSocket request using a fresh ``URLSessionWebSocketTask``.
  public func connect(_ request: WebSocketRequest) async throws(NetworkError) -> WebSocketConnection {
    let box = URLSessionWebSocketConnectionBox(request: request, configuration: self.configuration)
    return try await box.connect()
  }
}

private final class URLSessionWebSocketConnectionBox: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable {
  private let request: WebSocketRequest
  private let configuration: URLSessionConfiguration
  private let lock = NSLock()

  private var session: URLSession?
  private var task: URLSessionWebSocketTask?
  private var openContinuation: CheckedContinuation<String?, Error>?
  private var hasResolvedOpen = false
  private var closeFrame: WebSocketCloseFrame?

  init(
    request: WebSocketRequest,
    configuration: URLSessionConfiguration
  ) {
    self.request = request
    self.configuration = configuration
  }

  deinit {
    self.session?.invalidateAndCancel()
  }

  func connect() async throws(NetworkError) -> WebSocketConnection {
    let session = URLSession(configuration: self.configuration, delegate: self, delegateQueue: nil)
    let task = session.webSocketTask(with: self.request.urlRequest)
    task.maximumMessageSize = self.request.maximumMessageSize

    self.withLock {
      self.session = session
      self.task = task
    }

    do {
      let selectedSubprotocol = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
        self.withLock {
          self.openContinuation = continuation
        }
        task.resume()
      }

      let sendMessage: @Sendable (WebSocketMessage) async throws -> Void = { [box = self] message in
        try await box.send(message)
      }

      let receiveMessage: @Sendable () async throws -> WebSocketMessage = { [box = self] in
        try await box.receive()
      }

      let pingConnection: @Sendable () async throws -> Void = { [box = self] in
        try await box.ping()
      }

      let closeConnection: @Sendable (WebSocketCloseCode, Data?) async throws -> Void = { [box = self] code, reason in
        try await box.close(code: code, reason: reason)
      }

      return WebSocketConnection(
        selectedSubprotocol: selectedSubprotocol,
        send: sendMessage,
        receive: receiveMessage,
        ping: pingConnection,
        close: closeConnection
      )
    } catch {
      throw self.mapError(error)
    }
  }

  func send(_ message: WebSocketMessage) async throws(NetworkError) {
    let task = try self.requireTask()

    do {
      try await task.send(message.urlSessionMessage)
    } catch {
      throw self.mapError(error)
    }
  }

  func receive() async throws(NetworkError) -> WebSocketMessage {
    let task = try self.requireTask()

    do {
      let message = try await task.receive()
      return try WebSocketMessage(message)
    } catch {
      throw self.mapError(error)
    }
  }

  func ping() async throws(NetworkError) {
    let task = try self.requireTask()

    do {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        task.sendPing { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }
    } catch {
      throw self.mapError(error)
    }
  }

  func close(
    code: WebSocketCloseCode,
    reason: Data?
  ) async throws(NetworkError) {
    let task = try self.requireTask()
    let closeFrame = WebSocketCloseFrame(code: code, reason: reason)

    self.withLock {
      self.closeFrame = closeFrame
    }

    task.cancel(with: code.urlSessionCloseCode, reason: reason)
  }

  private func requireTask() throws(NetworkError) -> URLSessionWebSocketTask {
    self.lock.lock()
    defer { self.lock.unlock() }

    if let closeFrame = self.closeFrame {
      throw NetworkError.webSocketClosed(code: closeFrame.code, reason: closeFrame.reason)
    }

    guard let task = self.task else {
      throw NetworkError.invalidRequest("WebSocket task is unavailable.")
    }

    return task
  }

  private func mapError(_ error: any Error) -> NetworkError {
    self.withLock {
      if let closeFrame = self.closeFrame {
        return .webSocketClosed(code: closeFrame.code, reason: closeFrame.reason)
      }
      return NetworkError.from(error)
    }
  }

  private func resolveOpen(with result: Result<String?, Error>) {
    let continuation = self.withLock { () -> CheckedContinuation<String?, Error>? in
      guard !self.hasResolvedOpen else { return nil }
      self.hasResolvedOpen = true
      let continuation = self.openContinuation
      self.openContinuation = nil
      return continuation
    }

    continuation?.resume(with: result)
  }

  private func withLock<T>(_ body: () throws -> T) rethrows -> T {
    self.lock.lock()
    defer { self.lock.unlock() }
    return try body()
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol negotiatedProtocol: String?
  ) {
    self.resolveOpen(with: .success(negotiatedProtocol))
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    self.withLock {
      self.closeFrame = WebSocketCloseFrame(code: WebSocketCloseCode(closeCode), reason: reason)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    guard let error else { return }
    self.resolveOpen(with: .failure(self.mapError(error)))
  }
}

private extension WebSocketMessage {
  var urlSessionMessage: URLSessionWebSocketTask.Message {
    switch self {
    case .text(let string):
      .string(string)
    case .data(let data):
      .data(data)
    }
  }

  init(_ message: URLSessionWebSocketTask.Message) throws(NetworkError) {
    switch message {
    case .string(let string):
      self = .text(string)
    case .data(let data):
      self = .data(data)
    @unknown default:
      throw NetworkError.invalidRequest("Received an unknown WebSocket message kind.")
    }
  }
}

private extension WebSocketCloseCode {
  init(_ closeCode: URLSessionWebSocketTask.CloseCode) {
    self.init(rawValue: UInt16(closeCode.rawValue))
  }

  var urlSessionCloseCode: URLSessionWebSocketTask.CloseCode {
    URLSessionWebSocketTask.CloseCode(rawValue: Int(self.rawValue)) ?? .invalid
  }
}
