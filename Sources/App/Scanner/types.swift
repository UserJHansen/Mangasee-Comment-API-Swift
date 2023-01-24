import Foundation

struct RawReply: Codable, Hashable {
    let CommentID: String
    let UserID: String
    let Username: String
    let CommentContent: String
    let TimeCommented: String

    func convert(_ comment: Int) -> Reply {
        Reply(
            id: Int(CommentID)!,
            userId: Int(UserID)!,
            content: CommentContent,
            createdAt: Date(mangaseeTime: TimeCommented)!,
            commentId: comment
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CommentID)
    }
}

struct RawComment: Codable {
    // Another slight nitpick -- you can make these variable names
    // Swifty but encode them nicely using CodingKeys:
    // https://www.hackingwithswift.com/articles/119/codable-cheat-sheet
    // or you could even write a custom KeyDecodingStrategy:
    // https://developer.apple.com/documentation/foundation/jsondecoder/keydecodingstrategy
    let CommentID: String
    let UserID: String
    let Username: String
    let CommentContent: String
    let TimeCommented: String
    let ReplyCount: String
    let LikeCount: String
    let Liked: Bool
    let ShowReply: Bool
    let Replying: Bool
    let ReplyLimit: Int
    let ReplyMessage: String
    let Replies: [RawReply]

    func convert(discussionId id: Int) -> Comment {
        Comment(
            id: Int(CommentID)!,
            userId: Int(UserID)!,
            content: CommentContent,
            likes: Int(LikeCount)!,
            createdAt: Date(mangaseeTime: TimeCommented)!,
            discussionId: id
        )
    }

    func convert(mangaName id: String) -> Comment {
        Comment(
            id: Int(CommentID)!,
            userId: Int(UserID)!,
            content: CommentContent,
            likes: Int(LikeCount)!,
            createdAt: Date(mangaseeTime: TimeCommented)!,
            mangaName: id
        )
    }
}

struct MangaseeResponse<T: Codable>: Codable {
    let success: Bool
    let val: T
}
