import Foundation
import Hangar

@Entity("projects")
struct Project {
    @ID var id: UUID
    var key: String
    var name: String
    var ownerID: UUID
    var nextIssueNumber: Int
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
}

enum K {
    static let project = MultiKey<Project>("project")
    static let issue = MultiKey<Issue>("issue")
}

let repo = try await makeRepo()

guard let bench = try await repo.one(Project.where { $0.key == "BENCH" }) else {
    fatalError("seed data missing: BENCH project")
}

let multi = Multi()
    .insert(K.project, Changeset(Project.self)
        .change(\.id, UUID())
        .change(\.key, "SPINOFF")
        .change(\.name, "Spinoff Project")
        .change(\.ownerID, bench.ownerID)
        .change(\.nextIssueNumber, 2))
    .insert(K.issue) { results in
        let project = try results[K.project]
        return Changeset(Issue.self)
            .change(\.id, UUID())
            .change(\.projectID, project.id)
            .change(\.number, 1)
            .change(\.title, "Welcome to \(project.name)")
            .change(\.status, "open")
            .change(\.priority, "normal")
            .change(\.reporterID, project.ownerID)
    }

switch try await repo.run(multi) {
case .success(let values):
    let project = try values[K.project]
    let issue = try values[K.issue]
    print("created \(project.name) with first issue: \(issue.title)")
case .failure(let failure):
    print("step \(failure.key) failed: \(failure.error)")
}
