import AsyncHTTPClient
import CollectionConcurrencyKit
import Vapor

class ScanHandler {
    let client = HTTPClient(eventLoopGroupProvider: .createNew)
    let logger: Logger

    init(_ logger: Logger) {
        self.logger = logger
    }

    func getDiscussions() async {}

    func getMangaComments() async {}

    func scan() async {
        logger.info("Getting discussions...")
        await getDiscussions()

        logger.info("Finished, getting comments...")
        await getMangaComments()

        logger.info("Finished getting comments")
    }
}
