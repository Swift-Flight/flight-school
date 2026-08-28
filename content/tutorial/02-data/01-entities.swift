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
print(post)
