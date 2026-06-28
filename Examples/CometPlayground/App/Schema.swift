import CometSQLiteData
import Dependencies

extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    #if DEBUG
      defaultDatabase = try CometSQLiteDataSchema.defaultDatabase(eraseDatabaseOnSchemaChange: true)
    #else
      defaultDatabase = try CometSQLiteDataSchema.defaultDatabase()
    #endif
  }
}
