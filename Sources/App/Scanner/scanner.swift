import AsyncHTTPClient
import CollectionConcurrencyKit
import Fluent
import Vapor

public extension Sequence {
//    func limitedConcurrentForEach(
//        maxConcurrent limit: Int = 30,
//        withPriority priority: TaskPriority? = nil,
//        _ operation: @escaping (Element) async -> Void
//    ) async {
//        var i = 0
//        await withTaskGroup(of: Void.self) { group in
//            for element in self {
//                if i >= limit {
//                    await group.next()
//                }
//                i += 1
//
//                group.addTask(priority: priority) {
//                    await operation(element)
//                }
//            }
//        }
//    }

    func limitedConcurrentForEach(
        maxConcurrent limit: Int = 30,
        withPriority priority: TaskPriority? = nil,
        _ operation: @escaping (Element) async throws -> Void
    ) async rethrows {
        var i = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            for element in self {
                if i >= limit {
                    try await group.next()
                }
                i += 1

                group.addTask(priority: priority) {
                    try await operation(element)
                }
            }
        }
    }
}

enum ConLimits {
    static let network = 100
    static let db = 500
}

class ScanHandler {
    let client: Vapor.Client
    let logger: Logger
    let server: String
    let db: Database

    let usernames = CrossThreadSet<User>()
    let comments = CrossThreadSet<Comment>()
    let replies = CrossThreadSet<Reply>()

    func fill() async throws {
        logger.info("\(Date()) Filling cache...")
        await usernames.insert(try! await (User.query(on: db).all()))
        await comments.insert(try! await (Comment.query(on: db).all()))
        await replies.insert(try! await (Reply.query(on: db).all()))

        logger.info("\(Date()) Cache filled.")
    }

    func flush() async throws {
        logger.info("\(Date()) Saving Users...")

        await usernames.elements.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] user async in
            guard !user.exists else {
                logger.debug("Skipping \(user.name) (\(user.id!)))")
                return
            }
            logger.debug("Saving \(user.name) (\(user.id!)))")
            await user.saveWithRetry(on: db, logger)
        }

        logger.info("\(Date()) Saving comments")

        await comments.elements.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] comment async in
            guard !comment.needsUpdate else {
                await comment.update(on: db, logger)

                logger.debug("Updating comment \(comment.id!)")
                return
            }

            guard !comment.exists else {
                logger.debug("Skipping comment \(comment.id!)")
                return
            }

            logger.info("Saving comment \(comment.id!)")
            await comment.saveWithRetry(on: db, logger)
        }

        logger.info("\(Date()) Saving replies")
        await replies.elements.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] reply async in
            guard !reply.exists else {
                logger.debug("Skipping reply \(reply.id!)")
                return
            }

            logger.info("Saving reply \(reply.id!)")
            await reply.saveWithRetry(on: db, logger)
        }
    }

    init(_ logger: Logger, url server: String, db: Database, client: Vapor.Client) {
        self.logger = logger
        self.server = server
        self.db = db
        self.client = client
    }

    func scan() async throws {
        logger.info("\(Date()) Getting manga comments...")
        try await getMangaComments()

        logger.info("\(Date()) Finished, getting discussions...")
        await getDiscussions()

        logger.info("\(Date()) Finished getting comments")
    }
}
