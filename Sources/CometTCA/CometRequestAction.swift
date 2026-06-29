import Comet

/// A generic request lifecycle action for reducers that store ``CometRequestState``.
public enum CometRequestAction<Value: Sendable>: Sendable {
  case started
  case response(Result<Value, NetworkError>)
  case cancelled
}
