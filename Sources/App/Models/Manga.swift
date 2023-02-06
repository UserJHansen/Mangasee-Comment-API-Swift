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

  var exists = true
  init(id: String) {
    self.id = id

    // This works because this constructor is only called by the scanner
    exists = false
  }

  func saveWithRetry(on db: Database, _ logger: Logger) async {
    do {
      try await save(on: db)
    } catch {
      logger.error("Failed to save \(id!): \(error)")

      await saveWithRetry(on: db, logger)
    }
    exists = true
  }
}
