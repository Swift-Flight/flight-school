import Foundation
import Hangar

@Entity("issues")
struct Issue {
    @ID var id: UUID
    var projectID: UUID
    var title: String
    var status: String
}

let issue = Issue(id: UUID(), projectID: UUID(), title: "Login button unresponsive", status: "open")
print(issue)
