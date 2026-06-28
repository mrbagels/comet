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
private struct TestFeature {
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

@MainActor
@Test func effectRequestUsesInjectedClient() async {
  let store = TestStore(initialState: TestFeature.State()) {
    TestFeature()
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

@Test func cometRequestStateTracksValueLoadingAndFailure() {
  var state = CometRequestState<String>.idle

  #expect(state.value == nil)
  #expect(!state.isLoading)

  state.start()
  #expect(state.isLoading)
  #expect(state.value == nil)

  state.succeed("cached")
  #expect(state.value == "cached")
  #expect(!state.isLoading)

  state.start()
  #expect(state.isLoading)
  #expect(state.value == "cached")

  state.fail(.timeout)
  #expect(state.value == "cached")
  #expect(state.error?.isTimeoutError == true)
}
