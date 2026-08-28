import Foundation
import Hangar

@Entity("issues")
struct Issue {
    @ID var id: UUID
    var title: String
    var status: String
    var priority: String
}

let query = Issue.where { $0.status == "open" && $0.priority == "urgent" }
print(query.debugSQL)
