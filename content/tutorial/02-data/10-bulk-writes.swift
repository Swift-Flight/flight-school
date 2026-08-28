import Foundation
import Hangar

@Entity("projects")
struct Project {
    @ID var id: UUID
    var key: String
    var name: String
    var ownerID: UUID
}

@Entity("issues")
struct Issue {
    @ID var id: UUID
    var projectID: UUID
    var number: Int
    var title: String
    var status: String
    var priority: String
    var reporterID: UUID
    var updatedAt: Date
}

let repo = try await makeRepo()

guard let bench = try await repo.one(Project.where { $0.key == "BENCH" }) else {
    fatalError("seed data missing: BENCH project")
}

let demo = try await repo.insert(Project(
    id: UUID(), key: "BULK-\(UUID().uuidString.prefix(8))",
    name: "Bulk Demo", ownerID: bench.ownerID))

let rows = (1...3).map { n in
    Issue(
        id: UUID(), projectID: demo.id, number: n, title: "Backlog item \(n)",
        status: "open", priority: "low", reporterID: bench.ownerID, updatedAt: Date())
}
let stored = try await repo.insert(rows)
print("inserted \(stored.count) issues")

let closed = try await repo.update(Issue.where { $0.projectID == demo.id && $0.status == "open" }) {
    ($0.status.set(to: "closed"), $0.updatedAt.set(to: Date()))
}
print("closed \(closed) issues")

let purged = try await repo.delete(Issue.where { $0.projectID == demo.id && $0.status == "closed" })
print("purged \(purged) issues")
