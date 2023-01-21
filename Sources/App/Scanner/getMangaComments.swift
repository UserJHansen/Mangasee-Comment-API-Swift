import AsyncHTTPClient
import Fluent
import Vapor

struct SearchResponse: Codable {
    let i: String // Indexable name
    let s: String // Searchable name
    let a: [String] // Aliases
}

extension ScanHandler {
    func getMangaComments() async {
        var mangaNames = Set<String>()
        var data: ByteBuffer = .init()

        do {
            let response: HTTPClientResponse = try await client.execute(.init(url: "\(server)_search.php"), timeout: .seconds(30))
            data = try await response.body.collect(upTo: 1024 * 1024)
            let mangas = try JSONDecoder().decode([SearchResponse].self, from: data)

            logger.info("\(Date()) Downloaded list of \(mangas.count) mangas")

            mangaNames = Set(mangas.map { $0.i })
        } catch {
            logger.error("\(Date()) Error getting mangas: \(error) Data \(data.getString(at: 0, length: 1024)!)")
            return
        }

        let queue = mangaNames.map {
            var request = HTTPClientRequest(url: "\(server)manga/comment.get.php")
            request.body = .bytes(.init(string: "{\"IndexName\": \"\($0)\"}"))
            request.method = .POST

            return ($0, request)
        }

        let usernames = UserBuffer()
        for user in try! await (User.query(on: db).all()) {
            await usernames.addUser(user)
        }

        logger.info("\(Date()) Building \(queue.count) requests...")
        let comments = CommentBuffer<String>()
        let replies = ReplyBuffer()

        await queue.limitedConcurrentForEach(maxConcurrent: ConLimits.network) { [self] id, url in
            logger.debug("Starting request for manga \(id)")

            let data: ByteBuffer
            do {
                let response = try await client.execute(url, timeout: .seconds(60))
                data = try await response.body.collect(upTo: 1024 * 1024)
            } catch {
                logger.error("\(Date()) Error getting comments for manga \(id): \(error)")
                return
            }

            let commentList: [RawComment]
            do {
                commentList = try JSONDecoder().decode(MangaseeResponse<[RawComment]>.self, from: data).val
            } catch {
                logger.error("\(Date()) Error decoding comments for manga \(id): \(error) \(data.getString(at: 0, length: data.readableBytes)!)")
                return
            }

            for comment in commentList {
                logger.debug("Adding \(comment.Username) (\(comment.UserID)) to usernames")
                await usernames.addUser(User(id: Int(comment.UserID)!, name: comment.Username))
                await comments.addComment(id, comment)

                if Int(comment.ReplyCount)! != comment.Replies.count {
                    logger.debug("\(Date()) Loading replies for comment \(comment.CommentID) in manga \(id) ( \(comment.Replies.count) / \(comment.ReplyCount) replies)")

                    do {
                        var request = HTTPClientRequest(url: "\(server)manga/reply.get.php")
                        request.body = .bytes(.init(string: "{\"TargetID\": \(comment.CommentID)}"))
                        request.method = .POST
                        let response = try await client.execute(request, timeout: .seconds(30))
                        let data = try await response.body.collect(upTo: 1024 * 1024)
                        let newReplies = try JSONDecoder().decode(MangaseeResponse<[RawReply]>.self, from: data).val

                        for reply in newReplies {
                            logger.debug("Adding \(reply.Username) (\(reply.UserID)) to usernames")
                            await usernames.addUser(User(id: Int(reply.UserID)!, name: reply.Username))
                            await replies.addReply(Int(comment.CommentID)!, reply)
                            logger.debug("Added reply \(reply.CommentID) to comment \(comment.CommentID)")
                        }
                    } catch {
                        logger.error("\(Date()) Error loading replies: \(error)")
                    }
                } else {
                    for reply in comment.Replies {
                        logger.debug("Adding \(reply.Username) (\(reply.UserID)) to usernames")
                        await usernames.addUser(User(id: Int(reply.UserID)!, name: reply.Username))
                        await replies.addReply(Int(comment.CommentID)!, reply)
                    }
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

        let preexistingmangas = try! await Manga.query(on: db).all()
        await mangaNames.limitedConcurrentForEach(maxConcurrent: ConLimits.db) { [self] manga async in
            if preexistingmangas.contains(where: { $0.id == manga }) {
                logger.debug("Skipping \(manga)")
                return
            }
            logger.debug("Saving \(manga)")
            do {
                try await Manga(id: manga).save(on: db)
            } catch {
                logger.error("Failed to save manga \(manga): \(error)")
            }
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
