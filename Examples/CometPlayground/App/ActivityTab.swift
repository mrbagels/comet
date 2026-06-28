import CometSQLiteData
import Dependencies
import IssueReporting
import SwiftUI

private enum ActivityFilter: String, CaseIterable, Identifiable {
  case all
  case started
  case completed
  case failed
  case retried
  case socket

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
    case .socket:
      "Socket"
    }
  }

  func contains(_ kind: DemoActivityEntry.Kind) -> Bool {
    switch (self, kind) {
    case (.all, _),
      (.started, .started),
      (.completed, .completed),
      (.failed, .failed),
      (.retried, .retried),
      (.socket, .socket):
      true
    default:
      false
    }
  }

  func contains(_ record: CometActivityEventRecord) -> Bool {
    self.contains(record.activityEntry.kind)
  }
}

struct ActivityTab: View {
  let model: DemoCatalog
  @Dependency(\.defaultDatabase) private var database
  @FetchAll(CometActivityEventRecord.order { $0.occurredAt.desc() }.limit(50), animation: .default)
  private var persistedEvents
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

        Section("Saved History") {
          if filteredPersistedEvents.isEmpty {
            ContentUnavailableView(
              "No Saved Events",
              systemImage: "externaldrive",
              description: Text("Persisted activity appears here after the first run.")
            )
          } else {
            ForEach(filteredPersistedEvents) { record in
              NavigationLink(value: record) {
                PersistedActivityEventRow(record: record)
              }
            }
          }
        }
      }
      .navigationDestination(for: DemoActivityEntry.self) { event in
        ActivityDetailScreen(event: event)
      }
      .navigationDestination(for: CometActivityEventRecord.self) { record in
        ActivityDetailScreen(event: record.activityEntry)
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
            Label("Run current proof suite", systemImage: "play.circle")
          }
          .disabled(model.isRunning)

          Button(role: .destructive) {
            model.clearSession()
          } label: {
            Label("Clear session", systemImage: "trash")
          }
          .disabled(model.isRunning)

          Button(role: .destructive) {
            Task { await clearSavedHistoryButtonTapped() }
          } label: {
            Label("Clear saved history", systemImage: "externaldrive.badge.xmark")
          }
          .disabled(model.isRunning || persistedEvents.isEmpty)
        }
      }
    }
  }

  private var events: [DemoActivityEntry] {
    model.activityLog
  }

  private var filteredEvents: [DemoActivityEntry] {
    events.filter { event in
      let matchesFilter = filter.contains(event.kind)
      let matchesSearch = searchText.isEmpty || event.searchableText.localizedStandardContains(searchText)
      return matchesFilter && matchesSearch
    }
  }

  private var filteredPersistedEvents: [CometActivityEventRecord] {
    persistedEvents.filter { record in
      let event = record.activityEntry
      let matchesFilter = filter.contains(record)
      let matchesSearch = searchText.isEmpty || event.searchableText.localizedStandardContains(searchText)
      return matchesFilter && matchesSearch
    }
  }

  private func clearSavedHistoryButtonTapped() async {
    await withErrorReporting {
      try await CometSQLiteDataStore(database: database).deleteActivity()
    }
  }
}

private struct ActivitySummaryPanel: View {
  let latestSignal: DemoActivityEntry?
  @Binding var filter: ActivityFilter

  var body: some View {
    GlassPanel(tint: ThemeColor.ocean) {
      VStack(alignment: .leading, spacing: 8) {
        SectionEyebrow(text: "Latest Signal")
        Text(latestSignal?.rawValue ?? "Run any proof and the newest network event will land here.")
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
    case .socket:
      ThemeColor.ruby
    }
  }
}

private struct ActivityEventRow: View {
  let event: DemoActivityEntry

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: event.kind.symbolName)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(event.kind.accent)
        .frame(width: 38, height: 38)
        .background(event.kind.accent.opacity(0.12), in: .rect(cornerRadius: 14))

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

private struct PersistedActivityEventRow: View {
  let record: CometActivityEventRecord

  var body: some View {
    let event = record.activityEntry
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: event.kind.symbolName)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(event.kind.accent)
        .frame(width: 38, height: 38)
        .background(event.kind.accent.opacity(0.12), in: .rect(cornerRadius: 14))

      VStack(alignment: .leading, spacing: 6) {
        Text(event.title)
          .font(.system(.headline, design: .rounded).weight(.semibold))
          .foregroundStyle(ThemeColor.ink)

        Text(event.detail)
          .font(.system(.subheadline))
          .foregroundStyle(.secondary)
          .lineLimit(2)

        Text(record.occurredAt.formatted(date: .abbreviated, time: .standard))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct ActivityDetailScreen: View {
  let event: DemoActivityEntry

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
          SectionEyebrow(text: event.kind.title)

          Text(event.title)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(ThemeColor.ink)

          Text(event.detail)
            .font(.system(.title3))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        GlassPanel(tint: event.kind.accent) {
          SectionEyebrow(text: "Details")
          InspectorFieldList(fields: event.fields)
        }

        GlassPanel(tint: event.kind.accent) {
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

private extension CometActivityEventRecord {
  var activityEntry: DemoActivityEntry {
    var fields = [
      DemoInspectorField(label: "Source", value: self.source),
      DemoInspectorField(label: "Stored", value: self.occurredAt.formatted(date: .abbreviated, time: .standard))
    ]

    if let requestID {
      fields.append(DemoInspectorField(label: "Request ID", value: String(requestID.uuidString.prefix(8))))
    }
    if let method {
      fields.append(DemoInspectorField(label: "Method", value: method))
    }
    if let url {
      fields.append(DemoInspectorField(label: "URL", value: url))
    }
    if let statusCode {
      fields.append(DemoInspectorField(label: "Status", value: "\(statusCode)"))
    }
    if let durationMilliseconds {
      fields.append(
        DemoInspectorField(
          label: "Duration",
          value: "\(durationMilliseconds.formatted(.number.precision(.fractionLength(0...2))))ms"
        )
      )
    }
    if let retryAttempt {
      fields.append(DemoInspectorField(label: "Attempt", value: "\(retryAttempt)"))
    }
    if let retryDelayMilliseconds {
      fields.append(
        DemoInspectorField(
          label: "Delay",
          value: "\(retryDelayMilliseconds.formatted(.number.precision(.fractionLength(0...2))))ms"
        )
      )
    }
    if let errorSummary {
      fields.append(DemoInspectorField(label: "Error", value: errorSummary))
    }

    return DemoActivityEntry(
      id: self.id,
      kind: DemoActivityEntry.Kind(rawValue: self.kind) ?? .socket,
      title: self.title,
      detail: self.detail,
      fields: fields,
      rawValue: self.rawValue
    )
  }
}
