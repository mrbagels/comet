import Foundation

public final class EventBroadcaster<Event: Sendable>: @unchecked Sendable {
  public enum BufferingPolicy: Sendable, Equatable {
    case unbounded
    case bufferingNewest(Int)
    case bufferingOldest(Int)

    fileprivate var asyncStreamPolicy: AsyncStream<Event>.Continuation.BufferingPolicy {
      switch self {
      case .unbounded:
        .unbounded
      case .bufferingNewest(let limit):
        .bufferingNewest(limit)
      case .bufferingOldest(let limit):
        .bufferingOldest(limit)
      }
    }
  }

  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
  private let bufferingPolicy: BufferingPolicy

  public init(bufferingPolicy: BufferingPolicy = .bufferingNewest(100)) {
    self.bufferingPolicy = bufferingPolicy
  }

  public func stream() -> AsyncStream<Event> {
    let id = UUID()
    return AsyncStream(bufferingPolicy: self.bufferingPolicy.asyncStreamPolicy) { continuation in
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
