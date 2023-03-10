import Fluent

struct CreateReply: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema("replies")
      .field("id", .int, .identifier(auto: false), .required)
      .field("user_id", .int, .required, .references(User.schema, .id))
      .field("comment_id", .int, .required, .references(Comment.schema, .id))
      .field("content", .string, .required)
      .field("created_at", .datetime, .required)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema("replies").delete()
  }
}
