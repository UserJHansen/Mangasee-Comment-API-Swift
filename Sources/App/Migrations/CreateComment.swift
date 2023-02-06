import Fluent

struct CreateComment: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema("comments")
      .field("id", .int, .required, .identifier(auto: false))
      .field("user_id", .int, .required, .references(User.schema, .id))
      .field("content", .string, .required)
      .field("likes", .int, .required)
      .field("created_at", .datetime, .required)
      .field("reply_count", .int, .required)
      .field("discussion_id", .int, .references(Discussion.schema, .id))
      .field("manga_name", .string, .references(Manga.schema, .id))
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema("comments").delete()
  }
}
