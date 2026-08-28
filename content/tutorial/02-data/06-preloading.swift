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
    var status: String
    var reporterID: UUID
    var assigneeID: UUID?

    @BelongsTo(foreignKey: \Issue.reporterID) var reporter: Loadable<User>
    @BelongsTo(foreignKey: \Issue.assigneeID) var assignee: Loadable<User?>
}

let repo = try await makeRepo()

let issues = try await repo.all(
    Issue.where { $0.status == "open" }
        .limit(5)
        .preload(\.reporter)
        .preload(\.assignee))

for issue in issues {
    let reporter = try issue.reporter.get().displayName
    let assignee = try issue.assignee.get()?.displayName ?? "unassigned"
    print("\(issue.title) — reported by \(reporter), assignee: \(assignee)")
}
