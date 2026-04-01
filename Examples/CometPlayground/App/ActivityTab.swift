import SwiftUI

private enum ActivityFilter: String, CaseIterable, Identifiable {
  case all
  case started
  case completed
  case failed
  case retried

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all:
      "All"
    case .started:
      "Started"
    case .completed:
      "Completed"
    case .failed:
      "Failed"
    case .retried:
      "Retried"
    }
  }
}

private struct ActivityEvent: Hashable, Identifiable {
  let offset: Int
  let rawValue: String

  var id: String { "\(offset)-\(rawValue)" }

  var filter: ActivityFilter {
    if rawValue.hasPrefix("completed") { return .completed }
    if rawValue.hasPrefix("failed") { return .failed }
    if rawValue.hasPrefix("retry") { return .retried }
    return .started
  }

  var accent: Color {
    switch filter {
    case .all:
      ThemeColor.ocean
    case .started:
      ThemeColor.ocean
    case .completed:
      ThemeColor.mint
    case .failed:
      ThemeColor.ruby
    case .retried:
      ThemeColor.sunset
    }
  }

  var symbolName: String {
    switch filter {
    case .all:
      "waveform.path.ecg"
    case .started:
      "arrow.up.forward.circle"
    case .completed:
      "checkmark.circle"
    case .failed:
      "exclamationmark.triangle"
    case .retried:
      "arrow.clockwise"
    }
  }

  var title: String {
    rawValue.components(separatedBy: "•").first?.trimmingCharacters(in: .whitespaces) ?? rawValue
  }

  var detail: String {
    let parts = rawValue
      .components(separatedBy: "•")
      .dropFirst()
      .map { $0.trimmingCharacters(in: .whitespaces) }

    return parts.isEmpty ? "No secondary details recorded yet." : parts.joined(separator: " • ")
  }
}

struct ActivityTab: View {
  let model: DemoCatalog
  @State private var filter: ActivityFilter = .all
  @State private var searchText = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          ActivitySummaryPanel(
            latestSignal: model.activityLog.first,
            filter: $filter
          )
          .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
          .listRowBackground(Color.clear)
        }

        Section("Events") {
          if filteredEvents.isEmpty {
            ContentUnavailableView(
              "No Events Yet",
              systemImage: "waveform.path.ecg",
              description: Text("Run a proof to populate the live event stream.")
            )
          } else {
            ForEach(filteredEvents) { event in
              NavigationLink(value: event) {
                ActivityEventRow(event: event)
              }
            }
          }
        }
      }
      .navigationDestination(for: ActivityEvent.self) { event in
        ActivityDetailScreen(event: event)
      }
      .searchable(text: $searchText, prompt: "Search events")
      .scrollContentBackground(.hidden)
      .background(PlaygroundBackdrop())
      .navigationTitle("Activity")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            Task { await model.runCurrentModeProof() }
          } label: {
            Image(systemName: "play.circle")
          }

          Button {
            model.clearSession()
          } label: {
            Image(systemName: "trash")
          }
        }
      }
    }
  }

  private var events: [ActivityEvent] {
    model.activityLog.enumerated().map { ActivityEvent(offset: $0.offset, rawValue: $0.element) }
  }

  private var filteredEvents: [ActivityEvent] {
    events.filter { event in
      let matchesFilter = filter == .all || event.filter == filter
      let matchesSearch = searchText.isEmpty || event.rawValue.localizedStandardContains(searchText)
      return matchesFilter && matchesSearch
    }
  }
}

private struct ActivitySummaryPanel: View {
  let latestSignal: String?
  @Binding var filter: ActivityFilter

  var body: some View {
    GlassPanel(tint: ThemeColor.ocean) {
      VStack(alignment: .leading, spacing: 8) {
        SectionEyebrow(text: "Latest Signal")
        Text(latestSignal ?? "Run any proof and the newest network event will land here.")
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(latestSignal == nil ? .secondary : ThemeColor.ink)
          .fixedSize(horizontal: false, vertical: true)
      }

      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(ActivityFilter.allCases) { current in
            FilterChip(
              title: current.title,
              isSelected: current == filter,
              tint: tint(for: current)
            ) {
              filter = current
            }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private func tint(for filter: ActivityFilter) -> Color {
    switch filter {
    case .all, .started:
      ThemeColor.ocean
    case .completed:
      ThemeColor.mint
    case .failed:
      ThemeColor.ruby
    case .retried:
      ThemeColor.sunset
    }
  }
}

private struct ActivityEventRow: View {
  let event: ActivityEvent

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: event.symbolName)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(event.accent)
        .frame(width: 38, height: 38)
        .background(event.accent.opacity(0.12), in: .rect(cornerRadius: 14))

      VStack(alignment: .leading, spacing: 6) {
        Text(event.title)
          .font(.system(.headline, design: .rounded).weight(.semibold))
          .foregroundStyle(ThemeColor.ink)

        Text(event.detail)
          .font(.system(.subheadline))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct ActivityDetailScreen: View {
  let event: ActivityEvent

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
          SectionEyebrow(text: event.filter.title)

          Text(event.title)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(ThemeColor.ink)

          Text(event.detail)
            .font(.system(.title3))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        GlassPanel(tint: event.accent) {
          SectionEyebrow(text: "Raw Event")
          OutputConsole(value: event.rawValue)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 80)
    }
    .scrollIndicators(.hidden)
    .background(PlaygroundBackdrop())
    .navigationTitle("Event Detail")
    .navigationBarTitleDisplayMode(.inline)
  }
}
