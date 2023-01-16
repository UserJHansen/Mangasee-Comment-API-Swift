import Fluent
import Vapor

final class User: Model, Content {
  static let schema = "users"

  @ID(key: .id)
  var id: Int?

  @Field(key: "name")
  var mangaName: String?

  @Children(for: \.$user)
  var comments: [Comment]

  @Children(for: \.$user)
  var replies: [Reply]

  @Children(for: \.$user)
  var discussions: [Discussion]

  init() {}

  init(id: Int, mangaName: String?) {
    self.id = id
    self.mangaName = mangaName
  }
}
