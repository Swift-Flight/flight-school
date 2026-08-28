import FlightCore
import FlightWeb

struct IssueSummary: Codable, ResponseEncodable {
    let number: Int
    let status: String
}

@Controller
struct IssueController {
    @GetMapping("/issues/:number")
    func show(_ context: RequestContext) throws -> Response {
        guard let text = context.pathParam("number"), let number = Int(text) else {
            throw HTTPError(.badRequest, "issue number must be an integer")
        }
        guard number <= 200 else {
            throw HTTPError(.notFound, "no issue #\(number)")
        }
        return try Response.json(IssueSummary(number: number, status: "open"))
    }

    @PostMapping("/issues")
    func create(_ context: RequestContext) throws -> Response {
        try Response.json(IssueSummary(number: 201, status: "open"), status: .created)
    }

    @DeleteMapping("/issues/:number")
    func delete(_ context: RequestContext) -> Response {
        .noContent
    }
}
