import Fluent
import Vapor

final class Comment: Model, Content, Hashable {
  static let schema = "comments"

  @ID(custom: .id, generatedBy: .user)
  var id: Int?

  @Parent(key: "user_id")
  var user: User

  private var _username: String?
  var username: String {
    _username ?? user.name
  }

  @Field(key: "content")
  var content: String

  @Field(key: "likes")
  var likes: Int

  @Field(key: "created_at")
  var createdAt: Date

  @OptionalParent(key: "discussion_id")
  var discussion: Discussion?

  @OptionalParent(key: "manga_name")
  var manga: Manga?

  @Children(for: \.$comment)
  var replies: [Reply]

  // Unpushed replies
  var unpushedReplies: [Reply] = []

  var needsMoreReplies = false
  var exists = true

  init() {}

  init(
    id: Int, userId: User.IDValue, content: String, likes: Int,
    createdAt: Date, needsMoreReplies: Bool, discussionId: Discussion.IDValue? = nil,
    mangaName: Manga.IDValue? = nil
  ) {
    self.id = id
    $user.id = userId
    self.content = content
    self.likes = likes
    self.createdAt = createdAt
    self.needsMoreReplies = needsMoreReplies
    $discussion.id = discussionId
    $manga.id = mangaName

    exists = false
  }

  enum CodingKeys: CodingKey {
    case CommentID, UserID, Username, CommentContent, TimeCommented
    case ReplyCount, LikeCount, Liked, ShowReply, Replying, ReplyLimit
    case ReplyMessage, Replies
  }

  convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let commentId = Int(try container.decode(String.self, forKey: .CommentID))!
    let userId = Int(try container.decode(String.self, forKey: .UserID))!
    let content = try container.decode(String.self, forKey: .CommentContent)
    let likes = Int(try container.decode(String.self, forKey: .LikeCount))!
    let createdAt = try container.decode(Date.self, forKey: .TimeCommented)

    let replies = try container.decodeIfPresent([Reply].self, forKey: .Replies) ?? []
    replies.forEach { $0.$comment.id = commentId }

    self.init(
      id: commentId, userId: userId, content: content, likes: likes,
      createdAt: createdAt, needsMoreReplies: replies.count < Int(try container.decode(String.self, forKey: .ReplyCount))!
    )

    unpushedReplies = replies

    _username = try container.decode(String.self, forKey: .Username)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: Comment, rhs: Comment) -> Bool {
    lhs.id == rhs.id
  }
}
