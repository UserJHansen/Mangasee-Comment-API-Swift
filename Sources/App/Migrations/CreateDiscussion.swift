import Fluent

struct CreateDiscussion: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema("discussions")
      .field("id", .int, .required, .identifier(auto: false))
      .field("user_id", .int, .required, .references(User.schema, .id))
      .field("title", .string, .required)
      .field("content", .string, .required)
      .field("created_at", .datetime, .required)
      .field("type", .uint8, .required)
      .field("deleted", .bool, .required)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema("discussions").delete()
  }
}
