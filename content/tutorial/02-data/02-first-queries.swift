import Foundation
import Hangar

@Entity("posts")
struct Post {
    @ID var id: UUID
    var title: String
    var viewCount: Int
    var published: Bool
}

let base = Post.where { $0.published == true }

let recent = base.order { $0.viewCount.desc() }.limit(10)
let popular = base.where { $0.viewCount > 1_000 }

print(recent.debugSQL)
print(popular.debugSQL)
