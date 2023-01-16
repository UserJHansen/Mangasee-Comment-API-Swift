import Fluent

struct CreateUser: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema("users")
      .field("id", .int, .required)
      .field("name", .string, .required)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema("users").delete()
  }
}
