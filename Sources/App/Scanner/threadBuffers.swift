import Foundation

actor CommentBuffer<T: Hashable> {
    var comments: [T: [RawComment]]

    init() {
        comments = [:]
    }

    func addComment(_ id: T, _ comment: RawComment) {
        comments[id, default: []].append(comment)
    }
}

actor ReplyBuffer {
    var replies: [Int: [RawReply]]

    init() {
        replies = [:]
    }

    func addReply(_ id: Int, _ reply: RawReply) {
        replies[id, default: []].append(reply)
    }
}

actor UserBuffer {
    var users: [User]

    init() {
        users = []
    }

    func addUser(_ user: User) {
        users.append(user)
    }

    /// Adds multiple users at a given time.
    func addUsers(_ users: any Sequence<User>) {
        self.users.append(contentsOf: users)
    }
}

actor DiscussionBuffer {
    var discussions: [(Int, RawDiscussion)]

    init() {
        discussions = []
    }

    func addDiscussion(_ id: Int, _ discussion: RawDiscussion) {
        discussions.append((id, discussion))
    }
}
