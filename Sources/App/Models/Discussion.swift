import Fluent
import Vapor

enum PostType: UInt8 {
  case general = 0
  case request = 1
  case question = 2
  case announcement = 3
}
extension PostType: Codable {}

final class Discussion: Model, Content {
  static let schema = "discussions"

  @ID(custom: .id)
  var id: Int?

  @Parent(key: "user_id")
  var user: User

  @Field(key: "title")
  var title: String

  @Field(key: "content")
  var content: String

  @Field(key: "created_at")
  var createdAt: Date

  @Field(key: "type")
  var type: PostType

  @Field(key: "deleted")
  var deleted: Bool

  @Children(for: \.$discussion)
  var comments: [Comment]

  init() {}

  init(
    id: Int, userId: User.IDValue, title: String, content: String, createdAt: Date, type: PostType,
    deleted: Bool?
  ) {
    self.id = id
    self.$user.id = userId
    self.title = title
    self.content = content
    self.createdAt = createdAt
    self.type = type
    self.deleted = deleted ?? false
  }
}
