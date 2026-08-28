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

    @BelongsTo(foreignKey: \Issue.reporterID) var reporter: Loadable<User>
}

let issue = Issue(id: UUID(), title: "Login button unresponsive", reporterID: UUID())

do {
    let name = try issue.reporter.get().displayName
    print(name)
} catch {
    print(error)
}
