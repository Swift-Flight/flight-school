import FlightCore
import FlightWeb
import FlightWebTesting
import Foundation
import Testing

@testable import App

/// The three shapes the exercise describes, compiled against the real
/// testing API: a whole-app request test, a controller constructed
/// directly, and a container that runs the real modules with one
/// registration replaced.
@Suite("Testing shapes")
struct TutorialTestingTests {

    @Test("the index route answers with the configured application name")
    func index() async throws {
        let container = try TestContainer.build(
            configuration: Configuration(values: ["app.name": "TestApp"])
        ) {
            Components(HealthController.self)
        }
        let client = try TestClient(container: container)

        let response = await client.get("/")

        #expect(response.status == .ok)
        #expect(response.bodyText == "TestApp is flying")
    }

    @Test("a controller can be built straight from a container")
    func controllerDirectly() async throws {
        let container = try TestContainer.build {
            Components(UserController.self, UserService.self)
            FakeRepository(MockUserRepository(users: []))
        }
        let controller = try UserController(_flight: container)
        _ = try await controller.listUsers(.mock(container: container))
    }

    @Test("real modules, one registration overridden")
    func overridingOneRegistration() async throws {
        let fakeUsers = MockUserRepository(users: [])
        let container = try TestContainer.build {
            Components(UserController.self, UserService.self)
        } overriding: { container in
            container.override((any UserRepositoryProtocol).self, scope: .scoped) { _ in
                fakeUsers
            }
        }
        #expect(try container.resolve((any UserRepositoryProtocol).self) != nil)
    }
}
