import Fluent

struct CreateManga: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("mangas")
            .field("id", .string, .required, .identifier(auto: false))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("mangas").delete()
    }
}
