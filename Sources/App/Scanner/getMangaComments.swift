import AsyncHTTPClient
import Fluent
import Vapor
import Foundation
import CollectionConcurrencyKit

struct SearchResponse: Codable {
    let i: String // Indexable name
    let s: String // Searchable name
    let a: [String] // Aliases
}

extension ScanHandler {
    /// Returns a set of every available manga's name.
    func pullNamesFromServer() async throws -> Set<String> {
        var data: ByteBuffer = .init()

        let response: HTTPClientResponse = try await client.execute(.init(url: "\(server)_search.php"), timeout: .seconds(30))
        data = try await response.body.collect(upTo: 1024 * 1024)
        let mangas = try JSONDecoder().decode([SearchResponse].self, from: data)

        logger.info("\(Date()) Downloaded list of \(mangas.count) mangas")

        return Set(mangas.map { $0.i })
    }

    /// Takes a Set of manga names, then generates the associated HTTPClientRequest, and returns both.
    func generateRequestQueue(mangaNames: Set<String>) async throws -> [(name: String, request: HTTPClientRequest)] {
        return mangaNames.map { name in
            var request = HTTPClientRequest(url: "\(server)manga/comment.get.php")
            // Not using an encoder here for performance reasons
            request.body = .bytes(.init(string: """
            {"IndexName": "\(name)"}
            """
            ))
            request.method = .POST

            return (name, request)
        }
    }

    /// Takes a manga HTTPClientRequest and returns the comments from said request.
    func requestMangaComments(request req: HTTPClientRequest) async throws -> [RawComment] {
        let response = try await client.execute(req, timeout: .seconds(60))
        let data = try await response.body.collect(upTo: 1024 * 1024)

        return try JSONDecoder().decode(MangaseeResponse<[RawComment]>.self, from: data).val
    }

    /// Gets more replies to the given comment.
    func requestMoreReplies(to comment: RawComment) async throws -> [RawReply] {
        var request = HTTPClientRequest(url: "\(server)manga/reply.get.php")
        // Not using an encoder here for performance reasons
        request.body = .bytes(.init(string: """
        {"TargetID": "\(comment.CommentID)}"
        """))
        request.method = .POST
        let response = try await client.execute(request, timeout: .seconds(30))
        let data = try await response.body.collect(upTo: 1024 * 1024)
        let decodedBody =  try JSONDecoder().decode(MangaseeResponse<[RawReply]>.self, from: data)

        return decodedBody.val
    }

    func getMangaComments() async throws {
        let mangaNames = try await pullNamesFromServer()

        let queue = try await generateRequestQueue(mangaNames: mangaNames)

        // Add all the users from the database to the user buffer
        let usernames = UserBuffer()
        for user in try! await (User.query(on: db).all()) {
            await usernames.addUser(user)
        }

        logger.info("\(Date()) Building \(queue.count) requests...")
        // Set up our in-memory storage for comments and replies
        let comments = CommentBuffer<String>()
        let replies = ReplyBuffer()

        // NOTE: This may potentially cancel on a failed request. Make sure to test.
        try await queue.limitedConcurrentForEach(maxConcurrent: ConLimits.network) { [self] id, req in
            let commentList = try await requestMangaComments(request: req)
            
            for comment in commentList {
                logger.debug("Adding \(comment.Username) (\(comment.UserID)) to usernames")
                await usernames.addUser(User(id: Int(comment.UserID)!, name: comment.Username))
                await comments.addComment(id, comment)

                // TODO: Move all this to Comment.
                guard let replyCount = Int(comment.ReplyCount) else {
                    // TODO: Add actual errors here.
                    return
                }

                let replies: [RawReply]

                if replyCount != comment.Replies.count {
                    logger.debug("\(Date()) Loading replies for comment \(comment.CommentID) in manga \(id) ( \(comment.Replies.count) / \(comment.ReplyCount) replies)")
                    replies = try await requestMoreReplies(to: comment)
                } else {
                    logger.debug("\(Date()) Comment \(comment.CommentID) already had all replies in manga \(id) ( \(comment.Replies.count) / \(comment.ReplyCount) replies)")
                    replies = comment.replies
                }

                for reply in replies {
                    logger.debug("Adding \(reply.Username) (\(reply.UserID)) to usernames")
                    await usernames.addUser(User(id: Int(reply.UserID)!, name: reply.Username))
                    await replies.addReply(Int(comment.CommentID)!, reply)
                    logger.debug("Added reply \(reply.CommentID) to comment \(comment.CommentID)")
                }
            }
        }

        let preexistingusernames = try! await User.query(on: db).all()
        await usernames.users.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] user async in
            if preexistingusernames.contains(user) {
                logger.debug("Skipping \(user.name) (\(user.id!)))")
                return
            }
            logger.debug("Saving \(user.name) (\(user.id!)))")
            try? await user.save(on: db)
        }

        let preexistingManga = Set(try await Manga.query(on: db).all().concurrentMap { manga in
            try manga.requireID()
        })

        try await mangaNames.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] mangaName async in

            guard !preexistingManga.contains(mangaName) else {
                logger.debug("Skipping \(mangaName)")
                return
            }

            logger.debug("Saving \(mangaName)")
            try! await Manga(id: mangaName).save(on: db)
        }

        logger.info("\(Date()) Saving comments")
        let preexistingcomments = try! await Comment.query(on: db).all()
        let newComments = await comments.comments.flatMap { comment -> [(String, RawComment)] in
            comment.1.filter { comment in
                !preexistingcomments.contains(where: { $0.id == Int(comment.CommentID)! })
            }.map { res in (comment.0, res) }
        }.map { id, comment in
            comment.convert(mangaName: id)
        }

        await newComments.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] comment async in
            logger.info("Saving comment \(comment.id!) (\(comment.$manga.$id))")
            do {
                try await comment.save(on: db)
            } catch {
                logger.error("Failed to save comment \(comment.id!) (\(comment.$manga.$id)): \(error)")
            }
        }

        logger.info("\(Date()) Saving replies")
        let preexistingreplies = try! await Reply.query(on: db).all()
        for (id, reply) in await replies.replies {
            logger.debug("Saving \(reply.count) replies for comment \(id)")
            await reply.concurrentForEach { [self] reply async in
                let replyId = Int(reply.CommentID)!
                if preexistingreplies.contains(where: { $0.id == replyId }) {
                    logger.debug("Skipping reply \(reply.CommentID) (\(id))")
                    return
                }

                logger.info("Saving reply \(reply.CommentID) (\(id))")
                do {
                    try await reply.convert(id).save(on: db)
                } catch {
                    logger.error("Failed to save reply \(reply.CommentID) (\(id)): \(error)")
                }
            }
        }
    }
}
