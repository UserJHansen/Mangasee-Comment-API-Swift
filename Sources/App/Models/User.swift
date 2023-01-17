import Fluent
import Vapor

final class User: Model, Content {
  static let schema = "users"

  @ID(custom: .id)
  var id: Int?

  @Field(key: "name")
  var name: String

  @Children(for: \.$user)
  var comments: [Comment]

  @Children(for: \.$user)
  var replies: [Reply]

  @Children(for: \.$user)
  var discussions: [Discussion]

  init() {}

  init(id: Int, name: String) {
    self.id = id
    self.name = name
  }
}
