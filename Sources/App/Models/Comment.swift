import Fluent
import Vapor

final class Comment: Model, Content {
  static let schema = "comments"

  @ID(custom: .id, generatedBy: .user)
  var id: Int?

  @Parent(key: "user_id")
  var user: User

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

  init() {}

  init(
    id: Int, userId: User.IDValue, content: String, likes: Int, createdAt: Date,
    discussionId: Discussion.IDValue?,
    mangaName: Manga.IDValue?
  ) {
    self.id = id
    $user.id = userId
    self.content = content
    self.likes = likes
    self.createdAt = createdAt
    $discussion.id = discussionId
    $manga.id = mangaName
  }
}
