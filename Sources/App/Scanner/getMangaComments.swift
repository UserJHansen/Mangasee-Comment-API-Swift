import AsyncHTTPClient
import CollectionConcurrencyKit
import Fluent
import Foundation
import Jobs
import Vapor

struct SearchResponse: Codable {
    let i: String // Indexable name
    let s: String // Searchable name
    let a: [String] // Aliases
}

extension ScanHandler {
    /// Returns a set of every available manga's name.
    func pullNamesFromServer() async throws -> Set<String> {
        let response = try await client.get("\(server)_search.php")

        logger.info("\(Date()) Downloaded list of mangas")
        let mangas = try response.content.decode([SearchResponse].self)

        logger.info("\(Date()) Decoded list of \(mangas.count) mangas")

        return Set(mangas.map { $0.i })
    }

    /// Takes a manga HTTPClientRequest and returns the comments from said request.
    func requestMangaComments(name: String) async throws -> [Comment] {
        let request = try await client.post("\(server)manga/comment.get.php") { req in
            // Not using an encoder here for performance reasons
            try req.content.encode("""
            {"IndexName": "\(name)"}
            """)
        }

        return try request.content.decode(MangaseeResponse<[Comment]>.self).val
    }

    /// Takes a comment and returns the replies from said comment.
    func requestMoreReplies(to comment: Comment) async throws -> [Reply] {
        let request = try await client.post("\(server)manga/reply.get.php") { req in
            // Not using an encoder here for performance reasons
            try req.content.encode("""
            {"TargetID": "\(comment.id!)"}
            """)
        }

        return try request.content.decode(MangaseeResponse<[Reply]>.self).val
    }

    func processNames(_ mangaNames: Set<String>) async throws -> CrossThreadSet<[Comment]> {
        let result = CrossThreadSet<[Comment]>()
        var completed = 0
        var secs = 1
        let timer = Jobs.add(interval: .seconds(1)) { [self] in
            logger.info("\(Date()) Completed \(completed) requests, \(completed / secs)/s")
            secs += 1
        }
        try await mangaNames.limitedConcurrentForEach(maxConcurrent: ConLimits.network) { [self] id in
            let comments = try await requestMangaComments(name: id)

            for comment in comments {
                comment.$manga.id = id
            }

            completed += 1

            await result.insert(comments)
        }

        timer.stop()
        return result
    }

    func getMangaComments() async throws {
        logger.info("\(Date()) Getting manga names...")
        var mangaNames = try await pullNamesFromServer()

        logger.info("\(Date()) Completing \(mangaNames.count) requests...")

        let commentLists = try await processNames(mangaNames)

        let count = await commentLists.elements.reduce(0) { $0 + $1.count }
        logger.info("\(Date()) Finished requests, \(count) comments found")

        try await commentLists.elements.limitedConcurrentForEach(maxConcurrent: ConLimits.network) { [self] commentList in
            for comment in commentList {
                logger.debug("Adding \(comment.username) (\(comment.$user.id)) to usernames")
                await usernames.insert(User(id: comment.$user.id, name: comment.username))
                logger.debug("Added comment \(comment.id!) to manga \(comment.$manga.id!)")
                let result = await comments.insert(comment)
                if !result.inserted {
                    let oldComment = result.memberAfterInsert

                    if comment.likes != oldComment.likes {
                        oldComment.likes = comment.likes
                        oldComment.needsUpdate = true
                    }

                    if comment.replyCount != oldComment.replyCount {
                        let newreplies: [Reply]

                        if comment.needsMoreReplies {
                            logger.debug("\(Date()) Loading replies for comment \(comment.id!) in manga \(comment.$manga.id!)")
                            newreplies = try await requestMoreReplies(to: comment)
                        } else {
                            logger.debug("\(Date()) Comment \(comment.id!) already had all replies in manga \(comment.$manga.id!)")
                            newreplies = comment.unpushedReplies
                        }

                        for reply in newreplies {
                            logger.debug("Adding \(reply.username) (\(reply.$user.id)) to usernames")
                            await usernames.insert(User(id: reply.$user.id, name: reply.username))
                            reply.$comment.id = comment.id!
                            await replies.insert(reply)
                            logger.debug("Added reply \(reply.id!) to comment \(comment.id!)")
                        }
                    }
                }
            }
        }

        logger.info("\(Date()) Saving mangas")
        let mangas = CrossThreadSet<Manga>()
        await mangas.insert(try! await (Manga.query(on: db).all()))
        for manga in mangaNames {
            await mangas.insert(Manga(id: manga))
        }
        mangaNames = Set<String>()

        await mangas.elements.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] manga async in
            guard !manga.exists else {
                logger.debug("Skipping \(manga.id!)")
                return
            }

            logger.debug("Saving \(manga.id!)")
            await manga.saveWithRetry(on: db, logger)
        }

        logger.info("\(Date()) Saving users, comments, replies, and likes")
        try await flush()
    }
}
