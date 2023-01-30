import Fluent
import FluentSQLiteDriver
import Jobs
import Vapor

// configures your application
public func configure(_ app: Application) throws {
    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

    app.migrations.add(CreateComment())
    app.migrations.add(CreateDiscussion())
    app.migrations.add(CreateReply())
    app.migrations.add(CreateUser())
    app.migrations.add(CreateManga())

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .mangasee

    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Mangasee uses HTML for their API responses
    ContentConfiguration.global.use(decoder: decoder, for: .html)

    // register routes
    try routes(app)

    let scanner = ScanHandler(app.logger, url: Environment.get("SERVER") ?? "https://mangasee123.com/", db: app.db, client: app.client)
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
