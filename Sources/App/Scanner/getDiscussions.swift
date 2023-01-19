import AsyncHTTPClient
import Fluent
import Vapor

struct RawDiscussionList: Codable {
    let PostID: String
    let CountComment: String
    let Username: String
    let PostTitle: String
    let PostType: String
    let TimePosted: String
    let CommentOrder: String
    let TimeOrder: Bool
}

struct RawDiscussion: Codable {
    let Notification: String
    let PostContent: String
    let PostID: String
    let PostTitle: String
    let PostType: String
    let TimePosted: String
    let UserID: String
    let Username: String
    let Comments: [RawComment]
}

extension ScanHandler {
    func getDiscussions() async {
        var postIDs = Set<Int>()
        do {
            let response = try await client!.execute(.init(url: "\(server)discussion/index.get.php"), timeout: .seconds(30))
            let data = try await response.body.collect(upTo: 100 * 1024)
            let discussions = try JSONDecoder().decode(MangaseeResponse<[RawDiscussionList]>.self, from: data).val

            logger.info("\(Date()) Downloaded list of \(discussions.count) discussions")

            for row in try await Discussion.query(on: db).with(\.$user).all() {
                if row.deleted {
                    postIDs.remove(row.id!)
                } else {
                    postIDs.insert(row.id!)
                }
            }

            postIDs.formUnion(discussions.map { Int($0.PostID) ?? 0 })
            postIDs.remove(0)
        } catch {
            logger.error("\(Date()) Error getting discussions: \(error)")
            return
        }

        let queue = postIDs.map {
            var request = HTTPClientRequest(url: "\(server)discussion/post.get.php")
            request.body = .bytes(.init(string: "{\"id\": \($0)}"))
            request.method = .POST

            return ($0, request)
        }

        var usernames = Set<User>((try? await User.query(on: db).all()) ?? [])
        logger.info("Building \(queue.count) requests...")
        var discussions: [(Int, RawDiscussion)] = []
        var comments = [Int: [RawComment]]()
        var replies = [Int: Set<RawReply>]()

        await queue.limitedConcurrentForEach(maxConcurrent: 30) { [self] id, url in
            logger.debug("Starting request for discussion \(id)")

            let data: ByteBuffer
            do {
                let response = try await client!.execute(url, timeout: .seconds(60))
                data = try await response.body.collect(upTo: 1024 * 1024)
            } catch {
                logger.error("\(Date()) Error getting discussion \(id): \(error)")
                return
            }

            let discussion: RawDiscussion
            do {
                discussion = try JSONDecoder().decode(MangaseeResponse<RawDiscussion>.self, from: data).val
            } catch {
                // This discussion is deleted, mark it as such
                if let model = (try? await Discussion.query(on: db).filter(\.$id == id).first()) {
                    // This discussion already exists, update it
                    model.deleted = true
                    guard let _ = try? await model.save(on: db) else {
                        logger.error("Failed to update discussion \(id)")
                        return
                    }
                }
                logger.info("Deleted discussion \(id), \(error) \(data.getString(at: 0, length: data.readableBytes)!)")
                return
            }

            logger.debug("Adding \(discussion.Username) (\(discussion.UserID)) to usernames")
            usernames.insert(User(id: Int(discussion.UserID)!, name: discussion.Username))
            for comment in discussion.Comments {
                logger.debug("Adding \(comment.Username) (\(comment.UserID)) to usernames")
                usernames.insert(User(id: Int(comment.UserID)!, name: comment.Username))
                comments[id, default: []].append(comment)

                if Int(comment.ReplyCount)! != comment.Replies.count {
                    logger.info("\(Date()) Loading replies for comment \(comment.CommentID) in discussion \(id) ( \(comment.Replies.count) / \(comment.ReplyCount) replies)")

                    do {
                        var request = HTTPClientRequest(url: "\(server)discussion/post.reply.get.php")
                        request.body = .bytes(.init(string: "{\"TargetID\": \(comment.CommentID)}"))
                        request.method = .POST
                        let response = try await client!.execute(request, timeout: .seconds(30))
                        let data = try await response.body.collect(upTo: 1024 * 1024)
                        let newReplies = try JSONDecoder().decode(MangaseeResponse<[RawReply]>.self, from: data).val

                        for reply in newReplies {
                            logger.debug("Adding \(reply.Username) (\(reply.UserID)) to usernames")
                            usernames.insert(User(id: Int(reply.UserID)!, name: reply.Username))
                            if replies[Int(comment.CommentID)!, default: []].insert(reply).inserted {
                                logger.debug("Added reply \(reply.CommentID) to comment \(comment.CommentID)")
                            }
                        }
                    } catch {
                        logger.error("\(Date()) Error loading replies: \(error)")
                    }
                } else {
                    for reply in comment.Replies {
                        logger.debug("Adding \(reply.Username) (\(reply.UserID)) to usernames")
                        usernames.insert(User(id: Int(reply.UserID)!, name: reply.Username))
                        replies[Int(comment.CommentID)!, default: []].insert(reply)
                    }
                }
            }

            discussions.append((id, discussion))
        }

        let preexistingusernames = try! await User.query(on: db).all()
        await usernames.limitedConcurrentForEach(maxConcurrent: 60) { [self] user async in
            if preexistingusernames.contains(user) {
                logger.debug("Skipping \(user.name) (\(user.id!)))")
                return
            }
            logger.debug("Saving \(user.name) (\(user.id!)))")
            try? await user.save(on: db)
        }

        await discussions.limitedConcurrentForEach(maxConcurrent: 60) { [self] id, discussion in

            // MARK: - Format the discussion

            guard let type = PostType.fromName(discussion.PostType) else { logger.error("Weird type for discussion \(discussion.PostID)"); return }
            guard let userID = Int(discussion.UserID) else { logger.error("Weird user ID for \(discussion.Username) in discussion \(discussion.PostID)"); return }

            guard let date = Date(mangaseeTime: discussion.TimePosted) else { logger.error("Weird date for discussion \(discussion.PostID)"); return }

            // MARK: - Get the attached user

            let user = try? await User.query(on: db).filter(\.$id == userID).first()
            guard let user = user else {
                logger.error("User \(discussion.Username) (\(userID)) not found for discussion \(id)")
                return
            }

            if user.name != discussion.Username {
                user.name = discussion.Username
                do {
                    try await user.save(on: db)
                    logger.info("Username updated user to \(user.name) from \(discussion.Username)")
                } catch {
                    logger.error("Error updating username for \(user.name) to \(discussion.Username): \(error)")
                }
            }

            // MARK: - Save the discussion

            if let model = try? await Discussion.query(on: db).filter(\.$id == id).first() {
                if model.title != discussion.PostTitle || model.content != discussion.PostContent || model.createdAt != date || model.type != type {
                    logger.critical("Discussion \(discussion.PostID) has changed, we never should have gotten here! \(model.title) != \(discussion.PostTitle) || \(model.content) != \(discussion.PostContent) || \(model.createdAt) != \(date) || \(model.type) != \(type)")
                }
                return
            }

            let discussionModel = Discussion(
                id: id, userId: user.id!, title: discussion.PostTitle, content: discussion.PostContent,
                createdAt: date, type: type, deleted: false
            )

            logger.debug("Saving discussion \(id)")
            do {
                try await discussionModel.create(on: db)
            } catch {
                logger.error("Error saving discussion \(id): \(error)")
            }
            logger.info("\(Date()) Saved discussion \(id)")
        }

        logger.info("\(Date()) Saving comments")
        let preexistingcomments = try! await Comment.query(on: db).all()
        for (id, comment) in comments {
            await comment.concurrentForEach { [self] comment async in
                let commentId = Int(comment.CommentID)!
                if preexistingcomments.contains(where: { $0.id == commentId }) {
                    logger.debug("Skipping comment \(comment.CommentID) (\(id))")
                    return
                }
                logger.debug("Saving comment \(comment.CommentID) (\(id))")
                do {
                    try await comment.convert(discussionId: id).save(on: db)
                } catch {
                    logger.error("Failed to save comment \(comment.CommentID) (\(id)): \(error)")
                }
            }
        }

        logger.info("\(Date()) Saving replies")
        let preexistingreplies = try! await Reply.query(on: db).all()
        for (id, reply) in replies {
            await reply.concurrentForEach { [self] reply async in
                let replyId = Int(reply.CommentID)!
                if preexistingreplies.contains(where: { $0.id == replyId }) {
                    logger.debug("Skipping reply \(reply.CommentID) (\(id))")
                    return
                }

                logger.debug("Saving reply \(reply.CommentID) (\(id))")
                do {
                    try await reply.convert(id).save(on: db)
                } catch {
                    logger.error("Failed to save reply \(reply.CommentID) (\(id)): \(error)")
                }
            }
        }
    }
}
