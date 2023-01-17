import Fluent
import FluentSQLiteDriver
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

    let scanner = ScanHandler(app.logger)
    Timer.scheduledTimer(withTimeInterval: 4 * 60, repeats: true) {
        _ in
        Task(priority: .medium) {
            await scanner.scan()
        }
    }.fire()
}
