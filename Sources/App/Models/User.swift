import Fluent
import Vapor

final class User: Model, Content, Hashable, Equatable {
  static let schema = "users"

  @ID(custom: .id, generatedBy: .user)
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

  func hash(into hasher: inout Hasher) {
    hasher.combine($id.wrappedValue)
  }

  static func == (lhs: User, rhs: User) -> Bool {
    lhs.id == rhs.id
  }
}
