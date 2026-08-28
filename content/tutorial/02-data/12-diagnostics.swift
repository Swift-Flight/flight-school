import Foundation
import Hangar

@Entity("users")
struct User {
    @ID var id: UUID
    var displayName: String
}

@Entity("issues")
struct Issue {
    @ID var id: UUID
    var title: String
    var reporterID: UUID
    var createdAt: Date
}

@Sendable
func demonstrateRepeatedQueryDetection(_ repo: Repo) async throws {
    try await repo.detectingRepeatedQueries {
        // The exact mistake exercise 6 warns about: fetching each issue's
        // reporter one at a time instead of `.preload(\.reporter)`.
        let issues = try await repo.all(Issue.all.limit(25))
        for issue in issues {
            guard let reporter = try await repo.one(User.where { $0.id == issue.reporterID }) else {
                continue
            }
            print("issue \(issue.title) reported by \(reporter.displayName)")
        }
    }
}

var repo = try await makeRepo()

guard let someone = try await repo.all(User.all.limit(1)).first else {
    fatalError("seed data missing: no users")
}

let plan = try await repo.explain(
    Issue.where { $0.reporterID == someone.id }.order { $0.createdAt.desc() },
    mode: .analyze)
print(plan)

repo.diagnostics = .recommended

try await demonstrateRepeatedQueryDetection(repo)
