import Comet
import CometTCA
import ComposableArchitecture
import SwiftUI

@Reducer
struct TCADemoFeature {
  @ObservableState
  struct State {
    var fields: [DemoInspectorField] = []
    var output = "Run the request from a TCA reducer."
    var request: CometRequestState<DemoTodo> = .idle

    var status: DemoCatalog.DemoState.Status {
      switch request {
      case .idle:
        return .idle
      case .loading:
        return .running
      case .loaded:
        return .passed
      case .failed:
        return .failed
      }
    }
  }

  enum Action {
    case cancelButtonTapped
    case request(CometRequestAction<DemoTodo>)
    case resetButtonTapped
    case runButtonTapped
  }

  private enum CancelID {
    case request
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .cancelButtonTapped:
        state.request.cancel(keepingPreviousValue: false)
        state.output = "Request cancelled."
        state.fields = []
        return .cancel(id: CancelID.request)

      case .resetButtonTapped:
        state.request.reset()
        state.output = "Run the request from a TCA reducer."
        state.fields = []
        return .cancel(id: CancelID.request)

      case .request(.started):
        state.request.apply(.started)
        state.output = "Loading TodoRequest..."
        state.fields = [
          DemoInspectorField(label: "Request", value: "TodoRequest"),
          DemoInspectorField(label: "Reducer", value: "TCADemoFeature"),
          DemoInspectorField(label: "Effect", value: "Effect.trackedRequest"),
          DemoInspectorField(label: "State", value: "Loading")
        ]
        return .none

      case .request(.response(.success(let todo))):
        state.request.apply(.response(.success(todo)))
        state.output = """
        id: \(todo.id)
        user: \(todo.userId)
        title: \(todo.title)
        completed: \(todo.completed ? "yes" : "no")
        """
        state.fields = [
          DemoInspectorField(label: "Request", value: "TodoRequest"),
          DemoInspectorField(label: "Reducer", value: "TCADemoFeature"),
          DemoInspectorField(label: "Effect", value: "Effect.trackedRequest"),
          DemoInspectorField(label: "Completed", value: todo.completed ? "Yes" : "No")
        ]
        return .none

      case .request(.response(.failure(let error))):
        state.request.apply(.response(.failure(error)))
        state.output = error.debugSummary
        state.fields = [
          DemoInspectorField(label: "Request", value: "TodoRequest"),
          DemoInspectorField(label: "Reducer", value: "TCADemoFeature"),
          DemoInspectorField(label: "Effect", value: "Effect.trackedRequest"),
          DemoInspectorField(label: "Error", value: error.debugSummary)
        ]
        return .none

      case .request(.cancelled):
        state.request.apply(.cancelled)
        state.output = "Request cancelled."
        state.fields = []
        return .none

      case .runButtonTapped:
        return .trackedRequest(
          TodoRequest(),
          cancellationID: CancelID.request,
          action: Action.request
        )
      }
    }
  }
}

struct TCATab: View {
  let store: StoreOf<TCADemoFeature>

  init(store: StoreOf<TCADemoFeature>? = nil) {
    self.store = store ?? Store(initialState: TCADemoFeature.State()) {
      TCADemoFeature()
    } withDependencies: {
      $0.httpClient = DemoClientFactory.makeClient(mode: .mock)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          headerPanel
          statePanel
          outputPanel
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 120)
      }
      .scrollIndicators(.hidden)
      .background(PlaygroundBackdrop())
      .navigationTitle("TCA")
    }
  }

  private var headerPanel: some View {
    GlassPanel(tint: ThemeColor.plum) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          SectionEyebrow(text: "Reducer Flow")
          Text("TodoRequest")
            .font(.system(.title2, design: .rounded).weight(.bold))
            .foregroundStyle(ThemeColor.ink)
          Text("CometTCA request effects with injected HTTPClient dependency.")
            .font(.system(.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        StatusBadge(status: store.status)
      }

      HStack(spacing: 12) {
        Button {
          store.send(.runButtonTapped)
        } label: {
          Label(store.request.isLoading ? "Running" : "Run Request", systemImage: "play.circle.fill")
        }
        .primaryActionButton(tint: ThemeColor.plum)
        .disabled(store.request.isLoading)

        Button {
          store.send(store.request.isLoading ? .cancelButtonTapped : .resetButtonTapped)
        } label: {
          Label(store.request.isLoading ? "Cancel" : "Reset", systemImage: store.request.isLoading ? "xmark.circle" : "arrow.counterclockwise")
        }
        .secondaryActionButton()
      }
    }
  }

  private var statePanel: some View {
    GlassPanel(tint: ThemeColor.ocean) {
      SectionEyebrow(text: "State")

      if store.fields.isEmpty {
        Text("No request state has been emitted yet.")
          .font(.system(.body))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        InspectorFieldList(fields: store.fields)
      }
    }
  }

  private var outputPanel: some View {
    GlassPanel {
      SectionEyebrow(text: "Output")
      OutputConsole(value: store.output)
    }
  }
}
