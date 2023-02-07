import Fluent
import FluentPostgresDriver
import Jobs
import Vapor

// configures your application
public func configure(_ app: Application) throws {
    app.databases.use(.postgres(hostname: "localhost", username: "vapor", password: "vapor", database: "vapor"), as: .psql)

    app.migrations.add(CreateUser())
    app.migrations.add(CreateManga())
    app.migrations.add(CreateDiscussion())
    app.migrations.add(CreateComment())
    app.migrations.add(CreateReply())

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .mangasee

    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Mangasee uses HTML for their API responses
    ContentConfiguration.global.use(decoder: decoder, for: .html)

    // register routes
    try routes(app)

    struct Clean: AnyCommand {
        var help: String {
            "Cleans the database"
        }

        func run(using context: inout CommandContext) throws {
            context.application.logger.info("Cleaning database")
            try context.application.autoRevert().wait()
            try context.application.autoMigrate().wait()
        }
    }

    app.commands.use(Clean(), as: "clean")

    guard app.environment.commandInput.arguments.count == 0 else {
        return
    }

    let scanner = ScanHandler(app.logger, url: Environment.get("SERVER") ?? "https://mangasee123.com/", db: app.db, client: app.client)

    Task(priority: .high) {
        try await scanner.fill()
    }

    Jobs.add(interval: .seconds(10.0 * 60)) {
        Task {
            do {
                try await scanner.scan()
            } catch {
                print("Scanning failed: \(error)")
            }
        }
    }
}
