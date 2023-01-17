import Fluent
import Vapor

final class Manga: Model, Content {
  static let schema = "mangas"

  @ID(custom: .id)
  var id: String?

  @Children(for: \.$manga)
  var replies: [Comment]

  init() {}
}
