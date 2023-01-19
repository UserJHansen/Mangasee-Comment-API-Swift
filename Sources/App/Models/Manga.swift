import Fluent
import Vapor

final class Manga: Model, Content {
  static let schema = "mangas"

  @ID(custom: .id, generatedBy: .user)
  var id: String?

  @Children(for: \.$manga)
  var comments: [Comment]

  init() {}

  init(id: String) {
    self.id = id
  }
}
