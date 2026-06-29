import Foundation
import Testing
import Comet
import CometTCA
import CometTesting
import ComposableArchitecture
import Dependencies

private struct CometTCATestRequest: APIRequest {
  let path: Path = "value"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()
}

private enum TestFeatureError: Error, Equatable, Sendable {
  case message(String)
}

@Reducer
private struct DependencyClientFeature {
  @ObservableState
  struct State: Equatable {
    var value = ""
  }

  enum Action: Equatable {
    case load
    case response(Result<String, TestFeatureError>)
  }

  @Dependency(\.httpClient) var httpClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .load:
        return .request(
          CometTCATestRequest(),
          map: { result in
            .response(
              result.mapError { .message(String(describing: $0)) }
            )
          }
        )

      case .response(.success(let value)):
        state.value = value
        return .none

      case .response(.failure):
        return .none
      }
    }
  }
}

@MainActor
@Test func effectRequestUsesInjectedClient() async {
  let store = TestStore(initialState: DependencyClientFeature.State()) {
    DependencyClientFeature()
  } withDependencies: {
    $0.httpClient = .mock { _ in
      RawResponse(data: Data("hello".utf8), statusCode: 200)
    }
  }

  await store.send(.load)
  await store.receive(.response(.success("hello"))) {
    $0.value = "hello"
  }
}

@Reducer
private struct ExplicitClientFeature {
  @ObservableState
  struct State: Equatable {
    var value = ""
  }

  enum Action: Equatable {
    case load
    case response(Result<String, TestFeatureError>)
  }

  @Dependency(\.httpClient) var httpClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .load:
        return .request(
          CometTCATestRequest(),
          using: self.httpClient,
          map: { result in
            .response(
              result.mapError { .message(String(describing: $0)) }
            )
          }
        )

      case .response(.success(let value)):
        state.value = value
        return .none

      case .response(.failure):
        return .none
      }
    }
  }
}

@Reducer
private struct TrackedRequestFeature {
  @ObservableState
  struct State: Equatable {
    var request = CometRequestState<String>.idle

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.request.value == rhs.request.value
        && lhs.request.isIdle == rhs.request.isIdle
        && lhs.request.isLoading == rhs.request.isLoading
        && lhs.request.isLoaded == rhs.request.isLoaded
        && lhs.request.error?.debugSummary == rhs.request.error?.debugSummary
    }
  }

  enum Action {
    case cancel
    case load
    case request(CometRequestAction<String>)
  }

  private enum CancelID {
    case request
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .cancel:
        return .cancelTrackedRequest(id: CancelID.request, action: Action.request)

      case .load:
        return .trackedRequest(
          CometTCATestRequest(),
          cancellationID: CancelID.request,
          action: Action.request
        )

      case .request(let action):
        state.request.apply(action)
        return .none
      }
    }
  }
}

@Reducer
private struct ExplicitTrackedRequestFeature {
  @ObservableState
  struct State: Equatable {
    var request = CometRequestState<String>.idle

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.request.value == rhs.request.value
        && lhs.request.isIdle == rhs.request.isIdle
        && lhs.request.isLoading == rhs.request.isLoading
        && lhs.request.isLoaded == rhs.request.isLoaded
        && lhs.request.error?.debugSummary == rhs.request.error?.debugSummary
    }
  }

  enum Action {
    case load
    case request(CometRequestAction<String>)
  }

  @Dependency(\.httpClient) var httpClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .load:
        return .trackedRequest(
          CometTCATestRequest(),
          using: self.httpClient,
          action: Action.request
        )

      case .request(let action):
        state.request.apply(action)
        return .none
      }
    }
  }
}

@MainActor
@Test func effectRequestStillSupportsExplicitClient() async {
  let store = TestStore(initialState: ExplicitClientFeature.State()) {
    ExplicitClientFeature()
  } withDependencies: {
    $0.httpClient = .mock { _ in
      RawResponse(data: Data("explicit".utf8), statusCode: 200)
    }
  }

  await store.send(.load)
  await store.receive(.response(.success("explicit"))) {
    $0.value = "explicit"
  }
}

@MainActor
@Test func trackedRequestCancelEffectEmitsCancelledAction() async {
  let store = TestStore(initialState: TrackedRequestFeature.State()) {
    TrackedRequestFeature()
  } withDependencies: {
    $0.httpClient = .mock { (_: PreparedRequest) async throws(NetworkError) -> RawResponse in
      do {
        try await Task.sleep(for: .seconds(60))
        return RawResponse(data: Data("too late".utf8), statusCode: 200)
      } catch {
        throw NetworkError.cancelled
      }
    }
  }

  await store.send(.load)
  await store.receive({ action in
    guard case .request(.started) = action else { return false }
    return true
  }) {
    $0.request.start()
  }
  await store.send(.cancel)
  await store.receive({ action in
    guard case .request(.cancelled) = action else { return false }
    return true
  }) {
    $0.request.cancel()
  }
}

@MainActor
@Test func trackedRequestEmitsLifecycleActionsAndUpdatesRequestState() async {
  let store = TestStore(initialState: TrackedRequestFeature.State()) {
    TrackedRequestFeature()
  } withDependencies: {
    $0.httpClient = .mock { _ in
      RawResponse(data: Data("tracked".utf8), statusCode: 200)
    }
  }

  await store.send(.load)
  await store.receive({ action in
    guard case .request(.started) = action else { return false }
    return true
  }) {
    $0.request.start()
  }
  await store.receive({ action in
    guard case .request(.response(.success("tracked"))) = action else { return false }
    return true
  }) {
    $0.request.succeed("tracked")
  }
}

@MainActor
@Test func trackedRequestSupportsExplicitClient() async {
  let store = TestStore(initialState: ExplicitTrackedRequestFeature.State()) {
    ExplicitTrackedRequestFeature()
  } withDependencies: {
    $0.httpClient = .mock { _ in
      RawResponse(data: Data("explicit tracked".utf8), statusCode: 200)
    }
  }

  await store.send(.load)
  await store.receive({ action in
    guard case .request(.started) = action else { return false }
    return true
  }) {
    $0.request.start()
  }
  await store.receive({ action in
    guard case .request(.response(.success("explicit tracked"))) = action else { return false }
    return true
  }) {
    $0.request.succeed("explicit tracked")
  }
}

@MainActor
@Test func trackedRequestMapsNetworkCancellationToCancelledAction() async {
  let store = TestStore(initialState: TrackedRequestFeature.State()) {
    TrackedRequestFeature()
  } withDependencies: {
    $0.httpClient = .failing(with: .cancelled)
  }

  await store.send(.load)
  await store.receive({ action in
    guard case .request(.started) = action else { return false }
    return true
  }) {
    $0.request.start()
  }
  await store.receive({ action in
    guard case .request(.cancelled) = action else { return false }
    return true
  }) {
    $0.request.cancel()
  }
}

@Test func cometRequestStateTracksValueLoadingAndFailure() {
  var state = CometRequestState<String>.idle

  #expect(state.value == nil)
  #expect(state.isIdle)
  #expect(!state.isLoading)

  state.start()
  #expect(state.isLoading)
  #expect(state.value == nil)

  state.succeed("cached")
  #expect(state.value == "cached")
  #expect(state.isLoaded)
  #expect(!state.isLoading)

  state.start()
  #expect(state.isLoading)
  #expect(state.value == "cached")

  state.fail(.timeout)
  #expect(state.value == "cached")
  #expect(state.isFailed)
  #expect(state.error?.isTimeoutError == true)

  state.start()
  state.apply(.response(.success("fresh")))
  #expect(state.value == "fresh")
  #expect(state.isLoaded)

  state.start()
  state.cancel()
  #expect(state.value == "fresh")
  #expect(state.isLoaded)

  state.start()
  state.cancel(keepingPreviousValue: false)
  #expect(state.isIdle)

  state.succeed("reset")
  state.reset()
  #expect(state.isIdle)
}
