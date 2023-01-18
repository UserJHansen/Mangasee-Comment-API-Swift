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

    // register routes
    try routes(app)

    let scanner = ScanHandler(app.logger, url: Environment.get("SERVER") ?? "https://mangasee123.com/", db: app.db)
    Jobs.add(interval: .seconds(4.0 * 60)) {
        Task(priority: .medium) {
            await scanner.scan()
        }
    }
}
