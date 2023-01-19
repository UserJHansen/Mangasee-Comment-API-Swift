import AsyncHTTPClient
import CollectionConcurrencyKit
import Fluent
import Vapor

public extension Sequence {
    func limitedConcurrentForEach(
        maxConcurrent limit: Int = 30,
        withPriority priority: TaskPriority? = nil,
        _ operation: @escaping (Element) async -> Void
    ) async {
        var i = 0
        await withTaskGroup(of: Void.self) { group in
            for element in self {
                if i >= limit {
                    await group.next()
                }
                i += 1

                group.addTask(priority: priority) {
                    await operation(element)
                }
            }
        }
    }
}

class ScanHandler {
    var client: HTTPClient?
    let logger: Logger
    let server: String
    let db: Database

    init(_ logger: Logger, url server: String, db: Database) {
        self.logger = logger
        self.server = server
        self.db = db
    }

    func scan() async {
        client = HTTPClient(eventLoopGroupProvider: .createNew)
        logger.info("\(Date()) Getting discussions...")
        await getDiscussions()

        logger.info("\(Date()) Finished, getting comments...")
        await getMangaComments()

        logger.info("\(Date()) Finished getting comments")
        try? await client?.shutdown()
    }
}
