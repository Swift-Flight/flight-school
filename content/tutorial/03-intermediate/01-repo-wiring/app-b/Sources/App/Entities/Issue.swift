import FlightDataPostgres
import FlightWeb
import Foundation

@Entity("issues")
struct Issue: Encodable, Equatable, Sendable, ResponseEncodable {
    @ID var id: UUID
    var title: String
    var status: String
}
