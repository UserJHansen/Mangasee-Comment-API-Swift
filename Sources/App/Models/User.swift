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

  var exists = true

  init() {}

  init(id: Int, name: String) {
    self.id = id
    self.name = name

    // This works because this constructor is only called by the scanner
    exists = false
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine($id.wrappedValue)
  }

  static func == (lhs: User, rhs: User) -> Bool {
    lhs.id == rhs.id
  }

  func saveWithRetry(on db: Database, _ logger: Logger) async {
    do {
      try await save(on: db)
    } catch {
      logger.error("Error saving user \(name): \(error)")

      await saveWithRetry(on: db, logger)
    }
    exists = true
  }
}
