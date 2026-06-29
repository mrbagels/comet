import CometSQLiteData
import Dependencies
import IssueReporting

extension DependencyValues {
  mutating func bootstrapDatabase() {
    do {
      #if DEBUG
        defaultDatabase = try CometSQLiteDataSchema.defaultDatabase(eraseDatabaseOnSchemaChange: true)
      #else
        defaultDatabase = try CometSQLiteDataSchema.defaultDatabase()
      #endif
    } catch {
      reportIssue(error, "Falling back to an in-memory Comet database after bootstrap failed.")
      do {
        let database = try SQLiteData.defaultDatabase(path: nil)
        try CometSQLiteDataSchema.migrate(database)
        defaultDatabase = database
      } catch {
        reportIssue(error, "Unable to configure the fallback Comet database.")
      }
    }
  }
}
