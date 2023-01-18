struct RawReply: Codable {
    let CommentID: String
    let UserID: String
    let Username: String
    let CommentContent: String
    let TimeCommented: String
}

struct RawComment: Codable {
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
}

struct MangaseeResponse<T: Codable>: Codable {
    let success: Bool
    let val: T
}
