import Comet
import CometSQLiteData
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(
  .serialized,
  .dependencies {
    let database = try SQLiteData.defaultDatabase(path: nil)
    try CometSQLiteDataSchema.migrate(database)
    $0.defaultDatabase = database
  }
)
struct CometSQLiteDataTests {
  @Dependency(\.defaultDatabase) var database

  @Test func recordsNetworkEvents() async throws {
    let requestID = UUID(0)
    let store = CometSQLiteDataStore(database: self.database)

    try await store.record(
      event: .requestStarted(
        id: requestID,
        method: .get,
        url: URL(string: "https://example.com/users")!,
        metadata: RequestMetadata(name: "GetUsers", tags: ["users"])
      ),
      occurredAt: Date(timeIntervalSince1970: 1_000)
    )

    let records = try await store.recentActivity()
    #expect(records.count == 1)
    #expect(records[0].requestID == requestID)
    #expect(records[0].kind == "started")
    #expect(records[0].method == "GET")
    #expect(records[0].url == "https://example.com/users")
  }

  @Test func storesArtifacts() async throws {
    let store = CometSQLiteDataStore(database: self.database)

    try await store.insert(
      CometArtifactRecord(
        id: UUID(1),
        kind: "cassette",
        name: "Typed JSON",
        summary: "One exchange",
        contentType: "application/json",
        body: #"{"exchanges":[]}"#,
        createdAt: Date(timeIntervalSince1970: 2_000)
      )
    )

    let artifacts = try await store.artifacts(kind: "cassette")
    #expect(artifacts.count == 1)
    #expect(artifacts[0].name == "Typed JSON")
    #expect(artifacts[0].body.contains(#""exchanges""#))
  }
}

