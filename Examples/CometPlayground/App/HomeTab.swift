import SwiftUI

struct HomeTab: View {
  let model: DemoCatalog
  @Binding var selectedTab: AppTab

  private let gridColumns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          intro
          metricsGrid
          sessionPanel
          explorePanel
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 120)
      }
      .scrollIndicators(.hidden)
      .background(PlaygroundBackdrop())
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  private var intro: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionEyebrow(text: "Comet Playground")

      Text("Focused flows for Comet.")
        .font(.system(size: 40, weight: .bold, design: .rounded))
        .foregroundStyle(ThemeColor.ink)

      Text("Switch transports, run HTTP or socket proofs, and only move into details when you need the deeper output.")
        .font(.system(.title3))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Text(model.runSummary)
        .font(.system(.subheadline, design: .rounded).weight(.medium))
        .foregroundStyle(ThemeColor.ink.opacity(0.72))
    }
  }

  private var metricsGrid: some View {
    GroupedGlass(spacing: 12) {
      LazyVGrid(columns: gridColumns, spacing: 12) {
        ForEach(metrics) { metric in
          MetricTile(metric: metric)
        }
      }
    }
  }

  private var sessionPanel: some View {
    GlassPanel(tint: model.mode.accent) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          SectionEyebrow(text: "Session")
          Text("Choose a transport once, then jump into the HTTP or realtime flow you want to demonstrate.")
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

      Label(model.mode.blurb, systemImage: model.mode == .mock ? "checkmark.shield" : "globe")
        .font(.system(.body))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: 12) {
        Button {
          Task { await model.runMockProof() }
        } label: {
          Label("Run Mock Proof", systemImage: "checklist.checked")
        }
        .primaryActionButton(tint: ThemeColor.mint)

        Button {
          Task { await model.runCurrentModeProof() }
        } label: {
          Label("Run \(model.mode.title) Suite", systemImage: "bolt.horizontal.circle")
        }
        .secondaryActionButton()

        Button {
          model.clearSession()
        } label: {
          Label("Clear Session", systemImage: "arrow.counterclockwise")
        }
        .secondaryActionButton()
      }
    }
  }

  private var explorePanel: some View {
    GlassPanel {
      VStack(alignment: .leading, spacing: 10) {
        SectionEyebrow(text: "Explore")
        Text("Use dedicated tabs and detail screens when you need the full proof surface, a socket transcript, or the raw event history.")
          .font(.system(.body))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 12) {
        HomeShortcutButton(
          title: "Browse proof tracks",
          message: "Open category-driven proofs and drill into each scenario.",
          symbolName: "checklist"
        ) {
          selectedTab = .proofs
        }

        HomeShortcutButton(
          title: "Inspect activity",
          message: model.activityLog.first ?? "Run any proof to populate the event stream.",
          symbolName: "waveform.path.ecg"
        ) {
          selectedTab = .activity
        }
      }
    }
  }

  private var metrics: [DashboardMetric] {
    [
      DashboardMetric(
        title: "Passed",
        value: model.completedChecks.formatted(.number),
        note: "finished proofs",
        tint: ThemeColor.mint
      ),
      DashboardMetric(
        title: "Running",
        value: model.inFlightChecks.formatted(.number),
        note: "active requests",
        tint: ThemeColor.sunset
      ),
      DashboardMetric(
        title: "Failed",
        value: model.failedChecks.formatted(.number),
        note: "need review",
        tint: ThemeColor.ruby
      ),
      DashboardMetric(
        title: "Signals",
        value: model.activityLog.count.formatted(.number),
        note: "events captured",
        tint: ThemeColor.ocean
      )
    ]
  }
}

private struct HomeShortcutButton: View {
  let title: String
  let message: String
  let symbolName: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 14) {
        Image(systemName: symbolName)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(ThemeColor.ocean)
          .frame(width: 42, height: 42)
          .liquidPanel(tint: ThemeColor.ocean, cornerRadius: 16)

        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(ThemeColor.ink)

          Text(message)
            .font(.system(.subheadline))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Spacer(minLength: 0)

        Image(systemName: "arrow.right")
          .font(.system(.footnote, weight: .bold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .interactiveLiquidCapsule()
  }
}
