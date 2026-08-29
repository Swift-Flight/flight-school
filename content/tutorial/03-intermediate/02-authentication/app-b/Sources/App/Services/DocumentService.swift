import FlightCore
import FlightSecurityCore

@Service
struct DocumentService {
    // flight:hand-registered — FlightSecurityModule registers PrincipalHolder
    @Autowired var identity: PrincipalHolder

    func currentUsersSubject() throws -> String {
        guard let principal = identity.principal else {
            throw SecurityError.unauthenticated
        }
        return principal.subject
    }
}
