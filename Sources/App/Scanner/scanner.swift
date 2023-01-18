import AsyncHTTPClient
import CollectionConcurrencyKit
import Fluent
import Vapor

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
