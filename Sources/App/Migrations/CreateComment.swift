import Fluent

struct CreateComment: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema("comments")
      .field("id", .int, .required, .identifier(auto: false))
      .field("user_id", .int, .required, .references("users", "id"))
      .field("content", .string, .required)
      .field("likes", .int, .required)
      .field("created_at", .datetime, .required)
      .field("discussion_id", .int, .references("discussions", "id"))
      .field("manga_name", .string, .references("mangas", "name"))
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema("comments").delete()
  }
}
