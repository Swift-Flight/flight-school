import Foundation
import Hangar

@Entity("users")
struct User {
    @ID var id: UUID
    var displayName: String
}

@Entity("projects")
struct Project {
    @ID var id: UUID
    var name: String
    var ownerID: UUID
}

@Entity("issues")
struct Issue {
    @ID var id: UUID
    var title: String
    var projectID: UUID
}

struct Row: Decodable, Sendable {
    let title: String
    let owner: String
}

let repo = try await makeRepo()

let rows = try await repo.all(
    Issue.join(Project.self, on: { issue, project in issue.projectID == project.id })
        .join(User.self, on: { _, project, user in project.ownerID == user.id })
        .limit(3)
        .select(into: Row.self) { issue, project, user in
            (title: issue.title, owner: user.displayName)
        })

for row in rows {
    print("\(row.title) — project owned by \(row.owner)")
}
