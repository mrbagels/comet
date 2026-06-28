import Comet

/// Generic state for a request-driven value in TCA features.
public enum CometRequestState<Value: Sendable>: Sendable {
  case idle
  case loading(previous: Value?)
  case loaded(Value)
  case failed(NetworkError, previous: Value?)

  public var value: Value? {
    switch self {
    case .idle:
      return nil
    case .loading(let previous):
      return previous
    case .loaded(let value):
      return value
    case .failed(_, let previous):
      return previous
    }
  }

  public var error: NetworkError? {
    guard case .failed(let error, _) = self else { return nil }
    return error
  }

  public var isLoading: Bool {
    guard case .loading = self else { return false }
    return true
  }

  public mutating func start() {
    self = .loading(previous: self.value)
  }

  public mutating func succeed(_ value: Value) {
    self = .loaded(value)
  }

  public mutating func fail(_ error: NetworkError) {
    self = .failed(error, previous: self.value)
  }
}
