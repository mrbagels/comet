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

  private var outputPanel: some View {
    GlassPanel {
      SectionEyebrow(text: "Output")
      OutputConsole(value: state.output)
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
