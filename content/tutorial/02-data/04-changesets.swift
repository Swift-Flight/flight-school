import Foundation
import Hangar

@Entity("posts")
struct Post {
    @ID var id: UUID
    var title: String
    var viewCount: Int
    var published: Bool
}

let post = Post(id: UUID(), title: "Hello, Hangar", viewCount: 0, published: false)

let changeset = Changeset(original: post)
    .change(\.title, "")
    .validate(\.title, .length(1...200))

print(changeset.errors)
print(changeset.messagesByField)
print(changeset.isValid)
