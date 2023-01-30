import Fluent
import Vapor

final class Reply: Model, Content, Hashable {
  static let schema = "replies"

  @ID(custom: .id, generatedBy: .user)
  var id: Int?

  @Parent(key: "user_id")
  var user: User

  private var _username: String?
  var username: String {
    _username ?? user.name
  }

  @Parent(key: "comment_id")
  var comment: Comment

  @Field(key: "content")
  var content: String

  @Field(key: "created_at")
  var createdAt: Date

  var exists = true

  init() {}

  init(
    id: Int, userId: User.IDValue, content: String, createdAt: Date
  ) {
    self.id = id
    $user.id = userId
    self.content = content
    self.createdAt = createdAt

    exists = false
  }

  enum CodingKeys: CodingKey {
    case CommentID, UserID, Username, CommentContent, TimeCommented
  }

  convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let commentId = Int(try container.decode(String.self, forKey: .CommentID))!
    let userId = Int(try container.decode(String.self, forKey: .UserID))!
    let content = try container.decode(String.self, forKey: .CommentContent)
    let createdAt = try container.decode(Date.self, forKey: .TimeCommented)
    self.init(id: commentId, userId: userId, content: content, createdAt: createdAt)

    _username = try container.decode(String.self, forKey: .Username)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: Reply, rhs: Reply) -> Bool {
    lhs.id == rhs.id
  }
}
