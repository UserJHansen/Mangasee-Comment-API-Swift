import Fluent
import Vapor

final class Reply: Model, Content {
  static let schema = "replies"

  @ID(custom: .id)
  var id: Int?

  @Parent(key: "user_id")
  var user: User

  @Parent(key: "comment_id")
  var comment: Comment

  @Field(key: "content")
  var content: String

  @Field(key: "created_at")
  var createdAt: Date

  init() {}

  init(
    id: Int, userId: User.IDValue, content: String, createdAt: Date, commentId: Comment.IDValue
  ) {
    self.id = id
    $user.id = userId
    self.content = content
    self.createdAt = createdAt
    $comment.id = commentId
  }
}
