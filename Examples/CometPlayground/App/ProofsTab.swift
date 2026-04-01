import SwiftUI

struct ProofsTab: View {
  let model: DemoCatalog

  var body: some View {
    NavigationStack {
      List {
        Section {
          ProofsOverviewPanel(model: model)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        }

        Section("Tracks") {
          ForEach(DemoCatalog.DemoCategory.allCases) { category in
            NavigationLink(value: category) {
              ProofTrackRow(model: model, category: category)
            }
          }
        }

        if !recentDemos.isEmpty {
          Section("Recent Results") {
            ForEach(recentDemos) { demo in
              NavigationLink(value: demo) {
                DemoResultRow(model: model, demo: demo)
              }
            }
          }
        }
      }
      .navigationDestination(for: DemoCatalog.DemoCategory.self) { category in
        ProofCategoryScreen(model: model, category: category)
      }
      .navigationDestination(for: DemoCatalog.Demo.self) { demo in
        DemoDetailScreen(model: model, demo: demo)
      }
      .scrollContentBackground(.hidden)
      .background(PlaygroundBackdrop())
      .navigationTitle("Proofs")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await model.runCurrentModeProof() }
          } label: {
            Image(systemName: "play.circle")
          }
        }
      }
    }
  }

  private var recentDemos: [DemoCatalog.Demo] {
    DemoCatalog.Demo.allCases.filter { model.state(for: $0).status != .idle }
  }
}

private struct ProofsOverviewPanel: View {
  let model: DemoCatalog

  var body: some View {
    GlassPanel(tint: model.mode.accent) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          SectionEyebrow(text: "Focused Flow")
          Text("Open a track, pick a single HTTP or socket scenario, and keep the verification criteria next to the real output.")
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(ThemeColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        ModeBadge(mode: model.mode)
      }

      Picker("Client Mode", selection: Binding(
        get: { model.mode },
        set: { model.mode = $0 }
      )) {
        ForEach(DemoCatalog.ClientMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Text("Switch the transport here when you want every proof detail page to run against a different HTTP and WebSocket client setup.")
        .font(.system(.subheadline))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct ProofTrackRow: View {
  let model: DemoCatalog
  let category: DemoCatalog.DemoCategory

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: category.symbolName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(category.accent)
        .frame(width: 40, height: 40)
        .background(category.accent.opacity(0.12), in: .rect(cornerRadius: 14))

      VStack(alignment: .leading, spacing: 6) {
        Text(category.title)
          .font(.system(.headline, design: .rounded).weight(.semibold))
          .foregroundStyle(ThemeColor.ink)

        Text(category.subtitle)
          .font(.system(.subheadline))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      VStack(alignment: .trailing, spacing: 6) {
        Text(progressText)
          .font(.system(.headline, design: .rounded).weight(.bold))
          .foregroundStyle(category.accent)

        Text("verified")
          .font(.system(.caption))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private var progressText: String {
    let passed = category.demos.filter { model.state(for: $0).status == .passed }.count
    return "\(passed)/\(category.demos.count)"
  }
}

private struct DemoResultRow: View {
  let model: DemoCatalog
  let demo: DemoCatalog.Demo

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(demo.title)
          .font(.system(.headline, design: .rounded).weight(.semibold))
          .foregroundStyle(ThemeColor.ink)

        Text(model.state(for: demo).detail)
          .font(.system(.subheadline))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 0)

      StatusBadge(status: model.state(for: demo).status)
    }
    .padding(.vertical, 4)
  }
}

private struct ProofCategoryScreen: View {
  let model: DemoCatalog
  let category: DemoCatalog.DemoCategory

  var body: some View {
    List {
      Section {
        GlassPanel(tint: category.accent) {
          HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
              SectionEyebrow(text: category.title)
              Text(category.subtitle)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(ThemeColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text("\(passedCount)/\(category.demos.count)")
              .font(.system(.title2, design: .rounded).weight(.bold))
              .foregroundStyle(category.accent)
          }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
      }

      Section("Scenarios") {
        ForEach(category.demos) { demo in
          NavigationLink(value: demo) {
            DemoScenarioRow(model: model, demo: demo)
          }
        }
      }
    }
    .navigationTitle(category.title)
    .scrollContentBackground(.hidden)
    .background(PlaygroundBackdrop())
    .safeAreaInset(edge: .bottom) {
      VStack {
        Button {
          Task { await model.run(category: category) }
        } label: {
          Label("Run \(category.title) Track", systemImage: "play.circle.fill")
        }
        .primaryActionButton(tint: category.accent)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 8)
      .background(.clear)
    }
  }

  private var passedCount: Int {
    category.demos.filter { model.state(for: $0).status == .passed }.count
  }
}

private struct DemoScenarioRow: View {
  let model: DemoCatalog
  let demo: DemoCatalog.Demo

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: demo.symbolName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(demo.accent)
        .frame(width: 40, height: 40)
        .background(demo.accent.opacity(0.12), in: .rect(cornerRadius: 14))

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center, spacing: 8) {
          Text(demo.title)
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(ThemeColor.ink)

          StatusBadge(status: model.state(for: demo).status)
        }

        Text(demo.subtitle)
          .font(.system(.subheadline))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 4)
  }
}
