import Foundation

public final class EventBroadcaster<Event: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

  public init() {}

  public func stream() -> AsyncStream<Event> {
    let id = UUID()
    return AsyncStream { continuation in
      self.withLock {
        self.continuations[id] = continuation
      }
      continuation.onTermination = { [weak self] _ in
        self?.remove(id: id)
      }
    }
  }

  public func remove(id: UUID) {
    self.withLock {
      self.continuations[id] = nil
    }
  }

  public func emit(_ event: Event) {
    let continuations = self.withLock {
      Array(self.continuations.values)
    }
    for continuation in continuations {
      continuation.yield(event)
    }
  }

  public func finish() {
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
