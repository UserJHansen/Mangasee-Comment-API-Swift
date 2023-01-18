import Fluent
import Vapor

enum PostType: UInt8 {
  case general = 0
  case request = 1
  case question = 2
  case announcement = 3

  var name: String {
    switch self {
    case .general:
      return "General"
    case .request:
      return "Request"
    case .question:
      return "Question"
    case .announcement:
      return "Announcement"
    }
  }

  static func fromName(_ name: String) -> PostType? {
    switch name {
    case "General":
      return .general
    case "Request":
      return .request
    case "Question":
      return .question
    case "Announcement":
      return .announcement
    default:
      return .general
    }
  }
}

extension PostType: Codable {}

final class Discussion: Model, Content {
  static let schema = "discussions"

  @ID(custom: .id, generatedBy: .user)
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
    $user.id = userId
    self.title = title
    self.content = content
    self.createdAt = createdAt
    self.type = type
    self.deleted = deleted ?? false
  }
}
