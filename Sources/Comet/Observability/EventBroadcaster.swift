import Foundation

/// Controls how many activity events an ``HTTPClient`` buffers for each observer.
public enum NetworkActivityBufferingPolicy: Sendable, Equatable {
  case unbounded
  case bufferingNewest(Int)
  case bufferingOldest(Int)

  var asyncStreamPolicy: AsyncStream<NetworkEvent>.Continuation.BufferingPolicy {
    self.asyncStreamPolicy(for: NetworkEvent.self)
  }

  func asyncStreamPolicy<Event: Sendable>(
    for eventType: Event.Type
  ) -> AsyncStream<Event>.Continuation.BufferingPolicy {
    switch self {
    case .unbounded:
      .unbounded
    case .bufferingNewest(let limit):
      .bufferingNewest(Swift.max(0, limit))
    case .bufferingOldest(let limit):
      .bufferingOldest(Swift.max(0, limit))
    }
  }
}

final class EventBroadcaster<Event: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
  private let bufferingPolicy: AsyncStream<Event>.Continuation.BufferingPolicy

  init(bufferingPolicy: AsyncStream<Event>.Continuation.BufferingPolicy = .bufferingNewest(100)) {
    self.bufferingPolicy = bufferingPolicy
  }

  func stream() -> AsyncStream<Event> {
    let id = UUID()
    return AsyncStream(bufferingPolicy: self.bufferingPolicy) { continuation in
      self.withLock {
        self.continuations[id] = continuation
      }
      continuation.onTermination = { [weak self] _ in
        self?.remove(id: id)
      }
    }
  }

  func remove(id: UUID) {
    self.withLock {
      self.continuations[id] = nil
    }
  }

  func emit(_ event: Event) {
    let continuations = self.withLock {
      Array(self.continuations.values)
    }
    for continuation in continuations {
      continuation.yield(event)
    }
  }

  func finish() {
    let continuations = self.withLock {
      let active = Array(self.continuations.values)
      self.continuations.removeAll()
      return active
    }
    for continuation in continuations {
      continuation.finish()
    }
  }

  private func withLock<T>(_ body: () -> T) -> T {
    self.lock.lock()
    defer { self.lock.unlock() }
    return body()
  }
}
