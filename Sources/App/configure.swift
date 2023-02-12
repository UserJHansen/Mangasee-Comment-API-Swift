import Fluent
import FluentPostgresDriver
import Jobs
import Vapor

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

struct Start: Command {
    struct Signature: CommandSignature {
        @Flag(name: "with-prom", short: "e", help: "Starts the prometheus exporter")
        var prometheus: Bool
    }

    var help: String {
        "Starts the scanner"
    }

    func run(using context: CommandContext, signature: Signature) throws {
        context.application.logger.info("Starting scanner")
        if signature.prometheus == true {
            context.application.logger.info("Started prometheus exporter")
            try startProm(using: context)
        }

        var tempContext = context
        try context.application.commands.defaultCommand?.run(using: &tempContext)

        let scanner = ScanHandler(context.application.logger, url: Environment.get("SERVER") ?? "https://mangasee123.com/", db: context.application.db, client: context.application.client)

        Task(priority: .high) {
            try await scanner.fill()
        }

        Jobs.add(interval: .seconds(5.0 * 60)) {
            Task {
                do {
                    try await scanner.scan()
                } catch {
                    print("Scanning failed: \(error)")
                }
            }
        }
    }
}

// configures your application
public func configure(_ app: Application) throws {
    app.databases.use(.postgres(hostname: Environment.get("db-host") ?? "localhost", username: Environment.get("db-user") ?? "vapor", password: Environment.get("db-pass") ?? "vapor", database: Environment.get("db-name") ?? "vapor"), as: .psql)

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

    app.commands.use(Clean(), as: "clean")
    app.commands.use(Start(), as: "start")
}
