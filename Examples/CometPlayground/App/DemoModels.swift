import Foundation

struct DemoTodo: Codable, Sendable, Equatable, Identifiable {
  let userId: Int
  let id: Int
  let title: String
  let completed: Bool
}

struct WebSocketDemoPayload: Codable, Sendable, Equatable {
  let kind: String
  let mode: String
  let library: String
  let note: String
}

struct WebSocketDemoTranscript: Codable, Sendable, Equatable {
  let endpoint: String
  let transport: String
  let negotiatedSubprotocol: String?
  let outbound: WebSocketDemoPayload
  let inbound: WebSocketDemoPayload?
  let inboundText: String
  let closeCode: UInt16
}

struct DemoAPIError: Codable, Sendable, Equatable {
  let code: String
  let message: String
}

struct DemoInspectorField: Hashable, Identifiable, Sendable {
  let label: String
  let value: String

  var id: String { "\(label):\(value)" }
}

struct DemoActivityEntry: Hashable, Identifiable, Sendable {
  enum Kind: String, Sendable {
    case started
    case completed
    case failed
    case retried
    case socket
  }

  let id: UUID
  let kind: Kind
  let title: String
  let detail: String
  let fields: [DemoInspectorField]
  let rawValue: String

  init(
    id: UUID = UUID(),
    kind: Kind,
    title: String,
    detail: String,
    fields: [DemoInspectorField],
    rawValue: String
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.detail = detail
    self.fields = fields
    self.rawValue = rawValue
  }

  var searchableText: String {
    ([title, detail, rawValue] + fields.flatMap { [$0.label, $0.value] })
      .joined(separator: " ")
  }
}

struct DemoRequestInspection: Hashable, Sendable {
  let title: String
  let requestType: String
  let transport: String
  let method: String
  let url: String
  let timeout: String
  let fields: [DemoInspectorField]
  let bodyPreview: String
  let curlCommand: String?

  var hasCurlCommand: Bool {
    curlCommand != nil
  }
}

struct DemoResponseSnapshot: Hashable, Sendable {
  let title: String
  let summary: String
  let fields: [DemoInspectorField]
  let body: String
  let rawValue: String
}
