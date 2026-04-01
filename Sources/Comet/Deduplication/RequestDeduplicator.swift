import Foundation

public actor RequestDeduplicator {
  private struct Entry {
    let id: UUID
    let task: Task<RawResponse, Error>
  }

  private var inFlight: [String: Entry] = [:]

  public init() {}

  public func deduplicate(
    key: String,
    perform: @escaping @Sendable () async throws -> RawResponse
  ) async throws(NetworkError) -> RawResponse {
    if let existing = self.inFlight[key] {
      do {
        return try await existing.task.value
      } catch {
        throw .from(error)
      }
    }

    let id = UUID()
    let task = Task<RawResponse, Error> {
      try await perform()
    }
    self.inFlight[key] = Entry(id: id, task: task)

    Task {
      _ = await task.result
      self.clear(key: key, id: id)
    }

    do {
      return try await task.value
    } catch {
      throw .from(error)
    }
  }

  private func clear(key: String, id: UUID) {
    guard self.inFlight[key]?.id == id else { return }
    self.inFlight[key] = nil
  }
}
