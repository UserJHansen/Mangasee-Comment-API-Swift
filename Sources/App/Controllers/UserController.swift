import Fluent
import Vapor

struct UserController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    let users = routes.grouped("users")
    users.get(use: index)
    users.group(":userID") { user in
      user.get(use: show)
    }
  }

  func index(req: Request) async throws -> [User] {
    try await User.query(on: req.db).all()
  }

  func show(req: Request) async throws -> User {
    guard let userParam = req.parameters.get("userID") else {
      throw Abort(.badRequest)
    }

    let user: User?

    if let userID = Int(userParam) {
      user = try await User.query(on: req.db)
        .with(\.$comments)
        .filter(\.$id == userID)
        .first()
    } else {
      user = try await User.query(on: req.db)
        .with(\.$comments)
        .filter(\.$name == userParam)
        .first()
    }

    guard let user: User = user else {
      throw Abort(.notFound)
    }

    return user
  }
}
