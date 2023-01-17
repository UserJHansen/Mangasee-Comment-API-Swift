import Fluent
import Vapor

struct DiscussionController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    let discussions = routes.grouped("discussions")
    discussions.get(use: index)
    discussions.group(":discussionID") { discussion in
      discussion.get(use: show)
    }
  }

  func index(req: Request) async throws -> [Discussion] {
    try await Discussion.query(on: req.db).all()
  }

  func show(req: Request) async throws -> Discussion {
    guard let discussionID = req.parameters.get("discussionID", as: Int.self) else {
      throw Abort(.badRequest)
    }

    guard let discussion = try await (Discussion.query(on: req.db)
      .with(\.$comments) {
        $0.with(\.$replies)
      }
      .filter(\.$id == discussionID)
      .first())
    else {
      throw Abort(.notFound)
    }

    return discussion
  }
}
