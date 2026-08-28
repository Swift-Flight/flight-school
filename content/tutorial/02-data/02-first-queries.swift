import Foundation
import Hangar

@Entity("issues")
struct Issue {
    @ID var id: UUID
    var title: String
    var status: String
    var priority: String
    var updatedAt: Date
}

let base = Issue.where { $0.status == "open" }

let recent = base.order { $0.updatedAt.desc() }.limit(10)
let urgent = base.where { $0.priority == "urgent" }

print(recent.debugSQL)
print(urgent.debugSQL)
