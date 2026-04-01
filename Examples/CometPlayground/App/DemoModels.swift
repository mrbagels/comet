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
