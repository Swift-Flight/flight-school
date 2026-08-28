import Foundation
import Hangar

@Entity("issues")
struct Issue {
    @ID var id: UUID
    var title: String
    var status: String
}

let issue = Issue(id: UUID(), title: "Login button unresponsive", status: "open")

let changeset = Changeset(original: issue)
    .change(\.title, "")
    .validate(\.title, .length(1...200))

print(changeset.errors)
print(changeset.messagesByField)
print(changeset.isValid)
