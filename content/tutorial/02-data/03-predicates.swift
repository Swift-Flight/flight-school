import Foundation
import Hangar

@Entity("posts")
struct Post {
    @ID var id: UUID
    var title: String
    var viewCount: Int
    var published: Bool
}

let query = Post.where { $0.published == true && $0.viewCount > 100 }
print(query.debugSQL)
