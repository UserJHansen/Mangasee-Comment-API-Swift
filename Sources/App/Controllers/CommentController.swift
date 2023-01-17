import Fluent
import Vapor

struct CommentQuery: Content {
  let since: Date?
  let manga: String?
  let discussion: Int?
  let from: String?
  let at: String? // This is if you are trying to find if you were @ted in a comment
}

struct CommentController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("comments", use: index)
  }

  func index(req: Request) async throws -> Page<Comment> {
    var result = Comment.query(on: req.db)

    if let since = req.query[Date.self, at: "since"] {
      result = result.filter(\.$createdAt >= since)
    }

    if let manga = req.query[String.self, at: "manga"] {
      result = result.filter(\.$manga.$id == manga)
    }

    if let discussion = req.query[Int.self, at: "discussion"] {
      result = result.filter(\.$discussion.$id == discussion)
    }

    if let from = req.query[String.self, at: "from"] {
      result = result.join(User.self, on: \Comment.$user.$id == \User.$id).group(.or) { group in
        group.filter(User.self, \.$name == from)
        group.filter(\.$user.$id == Int(from) ?? 0)
      }
    }

    if let at = req.query[String.self, at: "at"] {
      result = result.join(Reply.self, on: \Reply.$comment.$id == \Comment.$id)
        .group(.or) {
          $0.filter(\.$content ~~ "@\(at)")
          $0.filter(Reply.self, \.$content ~~ "@\(at)")
        }
    }

    return try await result.paginate(for: req)
  }

  func show(req: Request) async throws -> User {
    guard let userParam = req.parameters.get("userID") else {
      throw Abort(.notFound)
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
