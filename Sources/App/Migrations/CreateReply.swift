import Fluent

struct CreateReply: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema("replies")
      .field("id", .int, .identifier(auto: false), .required)
      .field("user_id", .int, .required, .references("users", "id"))
      .field("comment_id", .int, .required, .references("comments", "id"))
      .field("content", .string, .required)
      .field("created_at", .datetime, .required)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema("replies").delete()
  }
}
