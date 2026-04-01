import Foundation

struct DemoTodo: Codable, Sendable, Equatable, Identifiable {
  let userId: Int
  let id: Int
  let title: String
  let completed: Bool
}
