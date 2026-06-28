import Comet
import Dependencies
import Foundation
import GRDB
@_exported import SQLiteData
@_exported import StructuredQueries
@_exported import StructuredQueriesSQLite

/// SQLiteData schema and migrations for persisting Comet diagnostics.
public enum CometSQLiteDataSchema {
  /// Creates the default SQLiteData database and runs the Comet persistence migrations.
  public static func defaultDatabase(eraseDatabaseOnSchemaChange: Bool = false) throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    migrator.eraseDatabaseOnSchemaChange = eraseDatabaseOnSchemaChange
    Self.registerMigrations(&migrator)
    try migrator.migrate(database)
    return database
  }

  /// Registers the Comet persistence tables with an existing app migrator.
  public static func registerMigrations(_ migrator: inout DatabaseMigrator) {
    migrator.registerMigration("Create Comet activity and artifact tables") { db in
      try #sql("""
        CREATE TABLE "cometActivityEvents" (
          "id" TEXT PRIMARY KEY NOT NULL,
          "requestID" TEXT,
          "source" TEXT NOT NULL,
          "kind" TEXT NOT NULL,
          "title" TEXT NOT NULL,
          "detail" TEXT NOT NULL,
          "method" TEXT,
          "url" TEXT,
          "statusCode" INTEGER,
          "durationMilliseconds" REAL,
          "retryAttempt" INTEGER,
          "retryDelayMilliseconds" REAL,
          "errorSummary" TEXT,
          "occurredAt" TEXT NOT NULL,
          "rawValue" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE INDEX "index_cometActivityEvents_on_occurredAt"
        ON "cometActivityEvents"("occurredAt" DESC)
        """)
        .execute(db)

      try #sql("""
        CREATE INDEX "index_cometActivityEvents_on_requestID"
        ON "cometActivityEvents"("requestID")
        """)
        .execute(db)

      try #sql("""
        CREATE INDEX "index_cometActivityEvents_on_source_kind"
        ON "cometActivityEvents"("source", "kind")
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "cometArtifacts" (
          "id" TEXT PRIMARY KEY NOT NULL,
          "kind" TEXT NOT NULL,
          "name" TEXT NOT NULL,
          "summary" TEXT,
          "contentType" TEXT NOT NULL,
          "body" TEXT NOT NULL,
          "createdAt" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE INDEX "index_cometArtifacts_on_createdAt"
        ON "cometArtifacts"("createdAt" DESC)
        """)
        .execute(db)

      try #sql("""
        CREATE INDEX "index_cometArtifacts_on_kind"
        ON "cometArtifacts"("kind")
        """)
        .execute(db)
    }
  }

  /// Runs the Comet persistence migrations against a database writer.
  public static func migrate(_ database: any DatabaseWriter) throws {
    var migrator = DatabaseMigrator()
    Self.registerMigrations(&migrator)
    try migrator.migrate(database)
  }
}

/// Persisted Comet diagnostic event suitable for SwiftUI observation with SQLiteData.
@Table("cometActivityEvents")
public struct CometActivityEventRecord: Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var requestID: UUID?
  public var source: String
  public var kind: String
  public var title: String
  public var detail: String
  public var method: String?
  public var url: String?
  public var statusCode: Int?
  public var durationMilliseconds: Double?
  public var retryAttempt: Int?
  public var retryDelayMilliseconds: Double?
  public var errorSummary: String?
  public var occurredAt: Date
  public var rawValue: String

  public init(
    id: UUID = UUID(),
    requestID: UUID? = nil,
    source: String,
    kind: String,
    title: String,
    detail: String,
    method: String? = nil,
    url: String? = nil,
    statusCode: Int? = nil,
    durationMilliseconds: Double? = nil,
    retryAttempt: Int? = nil,
    retryDelayMilliseconds: Double? = nil,
    errorSummary: String? = nil,
    occurredAt: Date = Date(),
    rawValue: String
  ) {
    self.id = id
    self.requestID = requestID
    self.source = source
    self.kind = kind
    self.title = title
    self.detail = detail
    self.method = method
    self.url = url
    self.statusCode = statusCode
    self.durationMilliseconds = durationMilliseconds
    self.retryAttempt = retryAttempt
    self.retryDelayMilliseconds = retryDelayMilliseconds
    self.errorSummary = errorSummary
    self.occurredAt = occurredAt
    self.rawValue = rawValue
  }

  public init(
    id: UUID = UUID(),
    event: NetworkEvent,
    occurredAt: Date = Date()
  ) {
    let shortID = String(event.id.uuidString.prefix(8))
    let name = event.displayName ?? "Request"

    switch event {
    case .requestStarted(_, let method, let url, _):
      let title = "\(name) started"
      let detail = "\(method.rawValue) \(url.absoluteString)"
      self.init(
        id: id,
        requestID: event.id,
        source: "http",
        kind: event.kind.rawValue,
        title: title,
        detail: detail,
        method: method.rawValue,
        url: url.absoluteString,
        occurredAt: occurredAt,
        rawValue: ([title, "id \(shortID)", detail]).joined(separator: " | ")
      )

    case .requestCompleted(_, let statusCode, let duration, _):
      let durationMilliseconds = duration.cometMilliseconds
      let title = "\(name) completed"
      let detail = "HTTP \(statusCode) in \(durationMilliseconds.formatted(.number.precision(.fractionLength(0...2))))ms"
      self.init(
        id: id,
        requestID: event.id,
        source: "http",
        kind: event.kind.rawValue,
        title: title,
        detail: detail,
        statusCode: statusCode,
        durationMilliseconds: durationMilliseconds,
        occurredAt: occurredAt,
        rawValue: ([title, "id \(shortID)", detail]).joined(separator: " | ")
      )

    case .requestFailed(_, let error, let duration, _):
      let durationMilliseconds = duration.cometMilliseconds
      let title = "\(name) failed"
      let detail = "\(error.debugSummary) in \(durationMilliseconds.formatted(.number.precision(.fractionLength(0...2))))ms"
      self.init(
        id: id,
        requestID: event.id,
        source: "http",
        kind: event.kind.rawValue,
        title: title,
        detail: detail,
        statusCode: error.statusCode,
        durationMilliseconds: durationMilliseconds,
        errorSummary: error.debugSummary,
        occurredAt: occurredAt,
        rawValue: ([title, "id \(shortID)", detail]).joined(separator: " | ")
      )

    case .requestRetried(_, let attempt, let delay, _):
      let retryDelayMilliseconds = delay.cometMilliseconds
      let title = "\(name) retry"
      let detail = "Attempt \(attempt) after \(retryDelayMilliseconds.formatted(.number.precision(.fractionLength(0...2))))ms"
      self.init(
        id: id,
        requestID: event.id,
        source: "http",
        kind: event.kind.rawValue,
        title: title,
        detail: detail,
        retryAttempt: attempt,
        retryDelayMilliseconds: retryDelayMilliseconds,
        occurredAt: occurredAt,
        rawValue: ([title, "id \(shortID)", detail]).joined(separator: " | ")
      )
    }
  }
}

/// Persisted Comet artifact such as cassette JSON, contract reports, or generated schemas.
@Table("cometArtifacts")
public struct CometArtifactRecord: Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var kind: String
  public var name: String
  public var summary: String?
  public var contentType: String
  public var body: String
  public var createdAt: Date

  public init(
    id: UUID = UUID(),
    kind: String,
    name: String,
    summary: String? = nil,
    contentType: String,
    body: String,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.summary = summary
    self.contentType = contentType
    self.body = body
    self.createdAt = createdAt
  }
}

/// Convenience wrapper around a SQLiteData database configured with ``CometSQLiteDataSchema``.
public struct CometSQLiteDataStore {
  public let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  @discardableResult
  public func record(
    event: NetworkEvent,
    occurredAt: Date = Date()
  ) async throws -> CometActivityEventRecord {
    let record = CometActivityEventRecord(event: event, occurredAt: occurredAt)
    try await self.insert(record)
    return record
  }

  public func insert(_ record: CometActivityEventRecord) async throws {
    try await self.database.write { db in
      try CometActivityEventRecord.upsert { record }.execute(db)
    }
  }

  public func insert(_ artifact: CometArtifactRecord) async throws {
    try await self.database.write { db in
      try CometArtifactRecord.upsert { artifact }.execute(db)
    }
  }

  public func recentActivity(limit: Int = 100) async throws -> [CometActivityEventRecord] {
    try await self.database.read { db in
      try CometActivityEventRecord
        .order { $0.occurredAt.desc() }
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func artifacts(kind: String? = nil, limit: Int = 50) async throws -> [CometArtifactRecord] {
    try await self.database.read { db in
      if let kind {
        try CometArtifactRecord
          .where { $0.kind.eq(kind) }
          .order { $0.createdAt.desc() }
          .limit(limit)
          .fetchAll(db)
      } else {
        try CometArtifactRecord
          .order { $0.createdAt.desc() }
          .limit(limit)
          .fetchAll(db)
      }
    }
  }

  public func deleteActivity() async throws {
    try await self.database.write { db in
      try CometActivityEventRecord.delete().execute(db)
    }
  }

  public func deleteArtifacts() async throws {
    try await self.database.write { db in
      try CometArtifactRecord.delete().execute(db)
    }
  }
}

extension CometSQLiteDataStore: @unchecked Sendable {}

private extension Duration {
  var cometMilliseconds: Double {
    let components = self.components
    let seconds = Double(components.seconds) * 1_000
    let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000
    return seconds + attoseconds
  }
}
