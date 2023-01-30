import AsyncHTTPClient
import CollectionConcurrencyKit
import Fluent
import Foundation
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

    func getMangaComments() async throws {
        logger.info("\(Date()) Getting manga names...")
        let mangaNames = try await pullNamesFromServer()

        logger.info("\(Date()) Getting users...")
        // Add all the users from the database to the user buffer
        let usernames = CrossThreadSet<User>()
        await usernames.insert(try! await (User.query(on: db).all()))

        logger.info("\(Date()) Building \(mangaNames.count) requests...")
        // Set up our in-memory storage for comments and replies
        let comments = CrossThreadSet<Comment>()
        await comments.insert(try! await (Comment.query(on: db).all()))

        let replies = CrossThreadSet<Reply>()
        await replies.insert(try! await (Reply.query(on: db).all()))

        // NOTE: This may potentially cancel on a failed request. Make sure to test.
        try await mangaNames.limitedConcurrentForEach(maxConcurrent: ConLimits.network) { [self] id in
            let commentList = try await requestMangaComments(name: id)

            for comment in commentList {
                logger.debug("Adding \(comment.username) (\(comment.$user.id)) to usernames")
                await usernames.insert(User(id: comment.$user.id, name: comment.username))
                logger.debug("Added comment \(comment.id!) to manga \(id)")
                await comments.insert(comment)

                let newreplies: [Reply]

                if comment.needsMoreReplies {
                    logger.info("\(Date()) Loading replies for comment \(comment.id!) in manga \(id)")
                    newreplies = try await requestMoreReplies(to: comment)
                } else {
                    logger.debug("\(Date()) Comment \(comment.id!) already had all replies in manga \(id)")
                    newreplies = comment.unpushedReplies
                }

                for reply in newreplies {
                    logger.debug("Adding \(reply.username) (\(reply.$user.id)) to usernames")
                    await usernames.insert(User(id: reply.$user.id, name: reply.username))
                    await replies.insert(reply)
                    logger.debug("Added reply \(reply.id!) to comment \(comment.id!)")
                }
            }
        }

        logger.info("\(Date()) Saving users")

        await usernames.elements.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] user async in
            guard !user.exists else {
                logger.debug("Skipping \(user.name) (\(user.id!)))")
                return
            }
            logger.debug("Saving \(user.name) (\(user.id!)))")
            do {
                try await user.save(on: db)
            } catch {
                logger.error("Failed to save \(user.name) (\(user.id!)): \(error)")
            }
        }

        let mangas = CrossThreadSet<Manga>()
        await mangas.insert(try! await (Manga.query(on: db).all()))
        for manga in mangaNames {
            await mangas.insert(Manga(id: manga))
        }

        await mangas.elements.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] manga async in
            guard !manga.exists else {
                logger.debug("Skipping \(manga.id!)")
                return
            }

            logger.debug("Saving \(manga.id!)")
            do {
                try await manga.save(on: db)
            } catch {
                logger.error("Failed to save \(manga.id!): \(error)")
            }
        }

        logger.info("\(Date()) Saving comments")

        await comments.elements.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] comment async in
            guard !comment.exists else {
                logger.debug("Skipping comment \(comment.id!) (\(comment.$manga.id!))")
                return
            }

            logger.info("Saving comment \(comment.id!) (\(comment.$manga.id!))")
            do {
                try await comment.save(on: db)
            } catch {
                logger.error("Failed to save comment \(comment.id!) (\(comment.$manga.id!)): \(error)")
            }
        }

        logger.info("\(Date()) Saving replies")
        await replies.elements.concurrentForEach { [self] reply async in
            guard !reply.exists else {
                logger.debug("Skipping reply \(reply.id!)")
                return
            }

            logger.info("Saving reply \(reply.id!)")
            do {
                try await reply.save(on: db)
            } catch {
                logger.error("Failed to save reply \(reply.id!): \(error)")
            }
        }
    }
}
