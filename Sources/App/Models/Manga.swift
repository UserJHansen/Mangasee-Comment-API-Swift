import Fluent
import Vapor

final class Manga: Model, Content, Hashable, Equatable {
    static func == (lhs: Manga, rhs: Manga) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }



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
