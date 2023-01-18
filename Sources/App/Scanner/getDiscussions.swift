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
        let discussions: [RawDiscussion] = await queue.concurrentCompactMap { [self] id, url -> RawDiscussion? in
            logger.debug("Starting request for discussion \(id)")

            let data: ByteBuffer
            do {
                let response = try await client!.execute(url, timeout: .seconds(30))
                data = try await response.body.collect(upTo: 1024 * 1024)
            } catch {
                logger.error("\(Date()) Error getting discussion \(id): \(error)")
                return nil
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
                        return nil
                    }
                }
                logger.info("Deleted discussion \(id), \(error) \(data.getString(at: 0, length: data.readableBytes)!)")
                return nil
            }

            guard let userID = Int(discussion.UserID) else { logger.error("Weird user ID for \(discussion.Username) in discussion \(discussion.PostID)"); return nil }

            usernames.insert(User(id: userID, name: discussion.Username))

            return discussion
        }.filter { $0 != nil }.map { $0! }

        await usernames.concurrentForEach { [self] user async in
            logger.debug("Saving \(user.name) (\(user.id!)))")
            try? await user.save(on: db)
        }

        await discussions.concurrentForEach { [self] discussion in

            // MARK: - Format the discussion

            guard let id = Int(discussion.PostID) else { logger.error("Weird ID for discussion \(discussion.PostID)"); return }
            guard let type = PostType.fromName(discussion.PostType) else { logger.error("Weird type for discussion \(discussion.PostID)"); return }
            guard let userID = Int(discussion.UserID) else { logger.error("Weird user ID for \(discussion.Username) in discussion \(discussion.PostID)"); return }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone(abbreviation: "PST")
            guard let date = formatter.date(from: discussion.TimePosted) else { logger.error("Weird date for discussion \(discussion.PostID)"); return }

            // MARK: - Get the attached user

            let user = try? await User.query(on: db).filter(\.$id == userID).first()
            guard let user = user else {
                logger.error("User \(discussion.Username) (\(userID)) not found for discussion \(discussion.PostID)")
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

            if let model = (try? await Discussion.query(on: db).filter(\.$id == id).first()) {
                // This discussion already exists, update it
                model.title = discussion.PostTitle
                model.content = discussion.PostContent
                model.createdAt = date
                model.type = type
                model.deleted = false
                model.$user.id = user.id!

                logger.debug("Updating discussion \(discussion.PostID)")
                do {
                    try await model.update(on: db)
                } catch {
                    logger.error("Error updating discussion \(discussion.PostID): \(error)")
                }

                logger.info("Updated discussion \(discussion.PostID)")
            } else {
                let discussionModel = Discussion(
                    id: id, userId: user.id!, title: discussion.PostTitle, content: discussion.PostContent,
                    createdAt: date, type: type, deleted: false
                )

                logger.debug("User: \(user.name)")
                logger.debug("Saving discussion \(discussion.PostID)")
                do {
                    try await discussionModel.create(on: db)
                } catch {
                    logger.error("Error saving discussion \(discussion.PostID): \(error)")
                }
                logger.info("Saved discussion \(discussion.PostID)")
            }
        }
    }
}
