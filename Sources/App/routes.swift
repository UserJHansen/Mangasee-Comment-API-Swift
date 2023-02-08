import Fluent
import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: UserController())
    try app.register(collection: DiscussionController())
    try app.register(collection: CommentController())

    app.get { _ in
        "Server is running"
    }
}
