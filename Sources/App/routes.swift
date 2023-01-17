import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { _ async in
        "It works!"
    }

    app.get("hello") { _ async -> String in
        "Hello, world!"
    }

    try app.register(collection: UserController())
    try app.register(collection: DiscussionController())
    try app.register(collection: CommentController())
}
