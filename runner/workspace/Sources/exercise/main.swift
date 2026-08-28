// The runner overwrites this file per session — this is only what ships
// baked into the image, so the very first `swift build` after a learner's
// first edit is warm rather than cold. Kept as a real, valid snippet-tier
// exercise (not an empty stub) so the image itself proves the workspace
// actually works before any session ever leases it.
import Foundation
import Hangar

@Entity("posts")
struct Post {
    @ID var id: UUID
    var title: String
    var viewCount: Int
}

let popular = Post.where { $0.viewCount > 1_000 }
    .order { $0.viewCount.desc() }
    .limit(20)

print(popular.debugSQL)
