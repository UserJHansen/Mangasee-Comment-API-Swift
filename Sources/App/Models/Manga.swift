import Fluent
import Vapor

final class Manga: Model, Content {
  static let schema = "mangas"

  @ID(key: .id)
  var id: String?

  @Children(for: \.$reply)
  var replies: [Comment]

  init() {}

}
