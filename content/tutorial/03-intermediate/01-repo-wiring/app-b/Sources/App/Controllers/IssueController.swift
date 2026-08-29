import FlightCore
import FlightDataPostgres
import FlightWeb
import Foundation

@Controller
struct IssueController {
    @Autowired var repo: Repo

    @GetMapping("/issues/:id")
    func show(_ context: RequestContext) async throws -> Issue {
        guard let idText = context.pathParam("id"), let id = UUID(uuidString: idText) else {
            throw HTTPError(.badRequest, "malformed id")
        }
        guard let issue = try await repo.one(Issue.where { $0.id == id }) else {
            throw HTTPError(.notFound, "no such issue")
        }
        return issue
    }
}
