import SwiftUI

struct DemoDetailScreen: View {
  let model: DemoCatalog
  let demo: DemoCatalog.Demo

  private let packageColumns = [
    GridItem(.adaptive(minimum: 140), spacing: 10)
  ]

  private var state: DemoCatalog.DemoState {
    model.state(for: demo)
  }

  private var requestInspection: DemoRequestInspection {
    model.requestInspection(for: demo)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        summaryPanel
        requestInspectorPanel
        traceTimelinePanel
        responseViewerPanel
        socketMonitorPanel
        cassetteViewerPanel
        proofBundlePanel
        verificationPanel
        packageSurfacePanel
        outputPanel
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 140)
    }
    .scrollIndicators(.hidden)
    .background(PlaygroundBackdrop())
    .navigationTitle(demo.title)
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      VStack {
        Button {
          Task { await model.run(demo) }
        } label: {
          Label(runButtonTitle, systemImage: runButtonSymbol)
        }
        .primaryActionButton(tint: demo.accent)
        .disabled(model.isRunning)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 8)
      .background(.clear)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionEyebrow(text: demo.category.title)

      Text(demo.subtitle)
        .font(.system(.title3))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        StatusBadge(status: state.status)
        ModeBadge(mode: model.mode)
      }
    }
  }

  private var summaryPanel: some View {
    GlassPanel(tint: demo.accent) {
      SectionEyebrow(text: "Status")

      Text(state.detail)
        .font(.system(.body, design: .rounded).weight(.medium))
        .foregroundStyle(ThemeColor.ink)
        .fixedSize(horizontal: false, vertical: true)

      if let latest = model.activityLog.first {
        Divider()
        Text(latest.rawValue)
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var verificationPanel: some View {
    GlassPanel {
      SectionEyebrow(text: "Verification")

      VStack(alignment: .leading, spacing: 12) {
        ForEach(demo.verificationChecklist(for: model.mode), id: \.self) { item in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(demo.accent)

            Text(item)
              .font(.system(.body))
              .foregroundStyle(ThemeColor.ink)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private var requestInspectorPanel: some View {
    let inspection = requestInspection
    return GlassPanel(tint: demo.accent) {
      SectionEyebrow(text: "Request Inspector")

      InspectorFieldList(
        fields: [
          DemoInspectorField(label: "Type", value: inspection.requestType),
          DemoInspectorField(label: "Transport", value: inspection.transport),
          DemoInspectorField(label: "Method", value: inspection.method),
          DemoInspectorField(label: "URL", value: inspection.url),
          DemoInspectorField(label: "Timeout", value: inspection.timeout)
        ] + inspection.fields
      )

      VStack(alignment: .leading, spacing: 10) {
        SectionEyebrow(text: "Body")
        OutputConsole(value: inspection.bodyPreview)
      }

      if let curlCommand = inspection.curlCommand {
        VStack(alignment: .leading, spacing: 10) {
          SectionEyebrow(text: "cURL")
          OutputConsole(value: curlCommand)
        }
      }
    }
  }

  private var packageSurfacePanel: some View {
    GlassPanel {
      SectionEyebrow(text: "Package Surface")

      LazyVGrid(columns: packageColumns, alignment: .leading, spacing: 10) {
        ForEach(demo.packageSurface, id: \.self) { item in
          Text(item)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(demo.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .liquidPanel(tint: demo.accent, cornerRadius: 18)
        }
      }
    }
  }

  private var responseViewerPanel: some View {
    GlassPanel(tint: demo.accent) {
      SectionEyebrow(text: "Response Viewer")

      if let response = state.response {
        VStack(alignment: .leading, spacing: 8) {
          Text(response.title)
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(ThemeColor.ink)

          Text(response.summary)
            .font(.system(.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        InspectorFieldList(fields: response.fields)

        VStack(alignment: .leading, spacing: 10) {
          SectionEyebrow(text: "Body")
          OutputConsole(value: response.body)
        }

        VStack(alignment: .leading, spacing: 10) {
          SectionEyebrow(text: "Snapshot")
          OutputConsole(value: response.rawValue)
        }
      } else {
        Text("Run the demo to inspect the latest response, failure, or socket result.")
          .font(.system(.body))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var traceTimelinePanel: some View {
    GlassPanel(tint: ThemeColor.ocean) {
      SectionEyebrow(text: "Trace Timeline")

      if let timeline = model.traceTimeline(for: demo) {
        VStack(alignment: .leading, spacing: 8) {
          Text(timeline.title)
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(ThemeColor.ink)

          Text(timeline.summary)
            .font(.system(.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        InspectorFieldList(fields: timeline.fields)

        VStack(alignment: .leading, spacing: 12) {
          SectionEyebrow(text: "Events")

          ForEach(timeline.events) { event in
            DetailRecordCard {
              Label(event.title, systemImage: event.kind.symbolName)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(event.kind.accent)

              Text(event.detail)
                .font(.system(.body))
                .foregroundStyle(ThemeColor.ink)
                .fixedSize(horizontal: false, vertical: true)

              InspectorFieldList(fields: event.fields)
            }
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          SectionEyebrow(text: "Trace Snapshot")
          OutputConsole(value: timeline.rawValue)
        }
      } else {
        Text("Run the demo to inspect the ordered request or socket activity for this scenario.")
          .font(.system(.body))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var socketMonitorPanel: some View {
    if demo.category == .realtime || state.socket != nil {
      GlassPanel(tint: ThemeColor.ruby) {
        SectionEyebrow(text: "Socket Monitor")

        if let socket = state.socket {
          VStack(alignment: .leading, spacing: 8) {
            Text(socket.title)
              .font(.system(.headline, design: .rounded).weight(.semibold))
              .foregroundStyle(ThemeColor.ink)

            Text("\(socket.transport) at \(socket.endpoint)")
              .font(.system(.body))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          InspectorFieldList(fields: socket.fields)

          VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "Frames")

            ForEach(socket.frames) { frame in
              DetailRecordCard {
                Label(frame.title, systemImage: frame.direction.symbolName)
                  .font(.system(.subheadline, design: .rounded).weight(.semibold))
                  .foregroundStyle(frame.direction.accent)

                Text(frame.payload)
                  .font(.system(.footnote, design: .monospaced))
                  .foregroundStyle(ThemeColor.ink)
                  .textSelection(.enabled)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Monitor Snapshot")
            OutputConsole(value: socket.rawValue)
          }
        } else {
          Text("Run a realtime demo to inspect socket frames, close codes, and transport details.")
            .font(.system(.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var outputPanel: some View {
    GlassPanel {
      SectionEyebrow(text: "Output")
      OutputConsole(value: state.output)
    }
  }

  private var proofBundlePanel: some View {
    GlassPanel(tint: ThemeColor.mint) {
      SectionEyebrow(text: "Proof Bundle")

      if let bundle = state.proofBundle {
        VStack(alignment: .leading, spacing: 8) {
          Text(bundle.title)
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(ThemeColor.ink)

          Text(bundle.summary)
            .font(.system(.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        InspectorFieldList(fields: bundle.fields)

        VStack(alignment: .leading, spacing: 10) {
          SectionEyebrow(text: "Markdown")
          OutputConsole(value: bundle.markdown)
        }
      } else {
        Text("Run the demo to package request, trace, response, cassette, and output into one persisted artifact.")
          .font(.system(.body))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var cassetteViewerPanel: some View {
    if demo.category != .realtime || state.cassette != nil {
      GlassPanel(tint: ThemeColor.plum) {
        SectionEyebrow(text: "Cassette Viewer")

        if let cassette = state.cassette {
          VStack(alignment: .leading, spacing: 8) {
            Text(cassette.title)
              .font(.system(.headline, design: .rounded).weight(.semibold))
              .foregroundStyle(ThemeColor.ink)

            Text(cassette.summary)
              .font(.system(.body))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          InspectorFieldList(fields: cassette.fields)

          if let replayOutput = cassette.replayOutput {
            VStack(alignment: .leading, spacing: 10) {
              SectionEyebrow(text: "Replay Verification")
              OutputConsole(value: replayOutput)
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "JSON")
            OutputConsole(value: cassette.json)
          }
        } else if model.mode == .mock {
          Text("Run the demo to record and inspect a deterministic mock cassette.")
            .font(.system(.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("Switch to Mock mode to generate deterministic cassette previews.")
            .font(.system(.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var runButtonTitle: String {
    switch state.status {
    case .idle:
      "Run Demo"
    case .running:
      "Running…"
    case .passed:
      "Run Again"
    case .failed:
      "Retry Demo"
    }
  }

  private var runButtonSymbol: String {
    switch state.status {
    case .idle:
      "play.circle.fill"
    case .running:
      "bolt.badge.clock.fill"
    case .passed:
      "arrow.clockwise.circle.fill"
    case .failed:
      "exclamationmark.arrow.circlepath"
    }
  }
}
