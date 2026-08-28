import Foundation
import Hangar

@Entity("authors")
struct Author {
    @ID var id: UUID
    var name: String
}

@Entity("posts")
struct Post {
    @ID var id: UUID
    var title: String
    var authorID: UUID

    @BelongsTo(foreignKey: \Post.authorID) var author: Loadable<Author>
}

let post = Post(id: UUID(), title: "Hello, Hangar", authorID: UUID())

do {
    let name = try post.author.get().name
    print(name)
} catch {
    print(error)
}
