import SwiftUI
import UIKit

enum ThemeColor {
  static let ink = Color(red: 0.12, green: 0.16, blue: 0.22)
  static let ocean = Color(red: 0.15, green: 0.47, blue: 0.90)
  static let sunset = Color(red: 0.90, green: 0.58, blue: 0.19)
  static let mint = Color(red: 0.20, green: 0.63, blue: 0.48)
  static let ruby = Color(red: 0.82, green: 0.30, blue: 0.34)
  static let plum = Color(red: 0.48, green: 0.37, blue: 0.83)

  static let backgroundTop = Color(red: 0.97, green: 0.98, blue: 1.00)
  static let backgroundBottom = Color(red: 0.96, green: 0.95, blue: 0.99)
  static let fallbackStroke = Color.black.opacity(0.08)
}

struct PlaygroundBackdrop: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          ThemeColor.backgroundTop,
          ThemeColor.backgroundBottom
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(ThemeColor.ocean.opacity(0.16))
        .frame(width: 360, height: 360)
        .blur(radius: 26)
        .offset(x: 140, y: -220)

      Circle()
        .fill(ThemeColor.mint.opacity(0.14))
        .frame(width: 280, height: 280)
        .blur(radius: 30)
        .offset(x: -150, y: -160)

      RoundedRectangle(cornerRadius: 180, style: .continuous)
        .fill(ThemeColor.plum.opacity(0.08))
        .frame(width: 320, height: 260)
        .rotationEffect(.degrees(18))
        .blur(radius: 20)
        .offset(x: 120, y: 340)
    }
    .ignoresSafeArea()
  }
}

struct GroupedGlass<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    Group {
      if #available(iOS 26, *) {
        GlassEffectContainer(spacing: spacing) {
          content
        }
      } else {
        content
      }
    }
  }
}

struct GlassPanel<Content: View>: View {
  let tint: Color?
  let cornerRadius: CGFloat
  let spacing: CGFloat
  @ViewBuilder let content: Content

  init(
    tint: Color? = nil,
    cornerRadius: CGFloat = 28,
    spacing: CGFloat = 18,
    @ViewBuilder content: () -> Content
  ) {
    self.tint = tint
    self.cornerRadius = cornerRadius
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      content
    }
    .padding(20)
    .liquidPanel(tint: tint, cornerRadius: cornerRadius)
  }
}

struct SectionEyebrow: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(.caption, design: .rounded).weight(.semibold))
      .textCase(.uppercase)
      .tracking(1.0)
      .foregroundStyle(.secondary)
  }
}

struct DashboardMetric: Identifiable {
  let title: String
  let value: String
  let note: String
  let tint: Color

  var id: String { title }
}

struct MetricTile: View {
  let metric: DashboardMetric

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionEyebrow(text: metric.title)

      Text(metric.value)
        .font(.system(size: 26, weight: .bold, design: .rounded))
        .foregroundStyle(ThemeColor.ink)
        .contentTransition(.numericText())

      Text(metric.note)
        .font(.system(.subheadline))
        .foregroundStyle(.secondary)

      Capsule()
        .fill(metric.tint)
        .frame(width: 36, height: 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .liquidPanel(tint: metric.tint, cornerRadius: 22)
  }
}

struct ModeBadge: View {
  let mode: DemoCatalog.ClientMode

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      SectionEyebrow(text: "Mode")

      Text(mode.title)
        .font(.system(.title3, design: .rounded).weight(.bold))
        .foregroundStyle(mode.accent)

      Text(mode.badgeDescription)
        .font(.system(.subheadline))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .liquidPanel(tint: mode.accent, cornerRadius: 22)
  }
}

struct StatusBadge: View {
  let status: DemoCatalog.DemoState.Status

  var body: some View {
    Text(status.label)
      .font(.system(.caption, design: .rounded).weight(.bold))
      .foregroundStyle(status.tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .interactiveLiquidCapsule(tint: status.tint.opacity(0.7))
  }
}

struct FilterChip: View {
  let title: String
  let isSelected: Bool
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .foregroundStyle(isSelected ? ThemeColor.ink : .secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 72)
    }
    .buttonStyle(.plain)
    .interactiveLiquidCapsule(tint: isSelected ? tint : nil)
  }
}

struct OutputConsole: View {
  let value: String
  @State private var didCopy = false
  @State private var resetTask: Task<Void, Never>?

  private var displayedValue: String {
    Self.prettyPrintedJSON(from: value) ?? value
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Spacer(minLength: 0)

        Button(action: copyOutput) {
          Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(didCopy ? ThemeColor.mint : ThemeColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .interactiveLiquidCapsule(tint: didCopy ? ThemeColor.mint : ThemeColor.ocean.opacity(0.7))
      }

      Text(displayedValue)
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(ThemeColor.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white.opacity(0.62))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(ThemeColor.fallbackStroke, lineWidth: 1)
    )
    .onDisappear {
      resetTask?.cancel()
    }
  }

  private func copyOutput() {
    UIPasteboard.general.string = displayedValue
    resetTask?.cancel()
    didCopy = true

    resetTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.2))
      guard !Task.isCancelled else { return }
      didCopy = false
    }
  }

  private static func prettyPrintedJSON(from value: String) -> String? {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedValue.first == "{" || trimmedValue.first == "[" else { return nil }
    guard let data = trimmedValue.data(using: .utf8) else { return nil }

    do {
      let object = try JSONSerialization.jsonObject(with: data)
      let prettyData = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
      )
      return String(decoding: prettyData, as: UTF8.self)
    } catch {
      return nil
    }
  }
}

struct InspectorFieldList: View {
  let fields: [DemoInspectorField]

  private let columns = [
    GridItem(.adaptive(minimum: 148), spacing: 10)
  ]

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
      ForEach(fields) { field in
        VStack(alignment: .leading, spacing: 6) {
          Text(field.label)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

          Text(field.value)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(ThemeColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.56))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(ThemeColor.fallbackStroke, lineWidth: 1)
        )
      }
    }
  }
}

extension View {
  @ViewBuilder
  func liquidPanel(tint: Color? = nil, cornerRadius: CGFloat = 28) -> some View {
    if #available(iOS 26, *) {
      if let tint {
        self.glassEffect(.regular.tint(tint.opacity(0.14)), in: .rect(cornerRadius: cornerRadius, style: .continuous))
      } else {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
      }
    } else {
      self
        .background(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
        )
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(ThemeColor.fallbackStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
    }
  }

  @ViewBuilder
  func interactiveLiquidCapsule(tint: Color? = nil) -> some View {
    if #available(iOS 26, *) {
      if let tint {
        self.glassEffect(.regular.tint(tint.opacity(0.16)).interactive(), in: .capsule)
      } else {
        self.glassEffect(.regular.interactive(), in: .capsule)
      }
    } else {
      self
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(ThemeColor.fallbackStroke, lineWidth: 1))
    }
  }

  @ViewBuilder
  func primaryActionButton(tint: Color) -> some View {
    if #available(iOS 26, *) {
      self
        .tint(tint)
        .buttonStyle(.glassProminent)
    } else {
      self.buttonStyle(FallbackProminentButtonStyle(tint: tint))
    }
  }

  @ViewBuilder
  func secondaryActionButton() -> some View {
    if #available(iOS 26, *) {
      self.buttonStyle(.glass)
    } else {
      self.buttonStyle(FallbackGlassButtonStyle())
    }
  }
}

private struct FallbackProminentButtonStyle: ButtonStyle {
  let tint: Color

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(.headline, design: .rounded).weight(.semibold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
      .background(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(tint.opacity(configuration.isPressed ? 0.82 : 0.96))
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
  }
}

private struct FallbackGlassButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(.headline, design: .rounded).weight(.semibold))
      .foregroundStyle(ThemeColor.ink)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .strokeBorder(ThemeColor.fallbackStroke, lineWidth: 1)
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
  }
}

extension DemoCatalog.ClientMode {
  var accent: Color {
    switch self {
    case .mock:
      ThemeColor.mint
    case .live:
      ThemeColor.ocean
    }
  }

  var badgeDescription: String {
    switch self {
    case .mock:
      "Deterministic transport"
    case .live:
      "Live network"
    }
  }
}

extension DemoCatalog.DemoCategory {
  var accent: Color {
    switch self {
    case .requests:
      ThemeColor.ocean
    case .transport:
      ThemeColor.plum
    case .cache:
      ThemeColor.mint
    case .failures:
      ThemeColor.sunset
    case .realtime:
      ThemeColor.ruby
    }
  }
}

extension DemoCatalog.Demo {
  var accent: Color {
    switch self {
    case .json:
      ThemeColor.ocean
    case .text:
      ThemeColor.sunset
    case .empty:
      ThemeColor.mint
    case .raw:
      ThemeColor.plum
    case .cacheLab:
      ThemeColor.mint
    case .timeout:
      ThemeColor.sunset
    case .unauthorized:
      ThemeColor.ruby
    case .rateLimited:
      ThemeColor.ocean
    case .serverError:
      ThemeColor.ruby
    case .malformedJSON:
      ThemeColor.plum
    case .cancelled:
      ThemeColor.sunset
    case .webSocket:
      ThemeColor.ruby
    case .webSocketClose:
      ThemeColor.ruby
    }
  }
}

extension DemoCatalog.DemoState.Status {
  var label: String {
    switch self {
    case .idle:
      "Idle"
    case .running:
      "Running"
    case .passed:
      "Passed"
    case .failed:
      "Needs Attention"
    }
  }

  var tint: Color {
    switch self {
    case .idle:
      .secondary
    case .running:
      ThemeColor.sunset
    case .passed:
      ThemeColor.mint
    case .failed:
      ThemeColor.ruby
    }
  }
}
