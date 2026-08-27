---
title: Authentication, brought rather than built
description: The TokenValidator seam, sessions vs. bearer tokens, a real login flow.
order: 2
---

Flight does not ship passwords, a login form, or a session store — on
purpose. Rolling your own auth is how applications get broken, and a
framework can't make that safe by trying harder; what it can do is turn a
*real* identity provider into configuration:

```yaml
# flight.yaml
security:
  oidc:
    issuer: "https://example.descope.com"
    audience: "my-flight-app"
```

```swift
modules: [
    FlightWebModule<FlightTransport>.self,
    FlightSecurityModule.self,
    AppModule.self,
]
```

That's the entire integration for any OIDC-compliant provider — Descope,
Keycloak, Auth0, Okta, Entra are the same validator with different
configuration values, not separate packages. The JWKS endpoint is resolved
by OIDC discovery automatically; cryptographic verification is JWTKit's, not
hand-rolled here.

## Reading who's making the request

```swift
@GetMapping("/documents")
func documents(_ context: RequestContext) async throws -> Response {
    let principal = try context.requirePrincipal()   // 401 when absent
    return try Response.json(try await repo.all(
        Document.where { $0.ownerID == principal.subject }))
}
```

`requirePrincipal()` throws a 401 for an unauthenticated request;
`context.principal` is the non-throwing form, `nil` rather than thrown, for
routes that behave differently for a guest instead of refusing them
outright. Either way the identity is request-scoped — `PrincipalHolder` is
resolved fresh per request, never shared or leaked between them — so a
`@Service` reads it by injecting it, the same as any other dependency:

```swift
@Service
final class DocumentService {
    @Autowired var identity: PrincipalHolder

    func currentUsersDocuments() async throws -> [Document] {
        guard let principal = identity.principal else { throw SecurityError.unauthenticated }
        ...
    }
}
```

## Bearer tokens are the default seam, not the only one

`OIDCTokenValidator` — what the config above wires up — validates a JWT.
Underneath, it satisfies one narrow protocol:

```swift
public protocol TokenValidator {
    func validate(_ token: String) async throws -> Principal
}
```

A provider that isn't a JWT at all — an opaque session token looked up
against your own store, say — is the same seam, conformed to directly:

```swift
struct OpaqueTokenValidator: TokenValidator {
    func validate(_ token: String) async throws -> Principal {
        let session = try await sessions.lookup(token)
        return Principal(subject: session.userID, roles: session.roles)
    }
}
```

Both shapes end at the same place — a `Principal`, read the same way by
every handler and service — which is the actual design: Flight standardizes
*what a validated identity looks like once you have one*, and stays
deliberately agnostic about whether that identity came from a signed
bearer token or a server-side session lookup.

## Enforcement is a separate decision from authentication

`FlightSecurityModule` installs its `Authentication` middleware
automatically — but that middleware always continues, whether or not a
token was presented, so a public route stays public even with the module
installed. Requiring a principal is something the application opts into,
either per route with a handler-level guard (`requirePrincipal()`, as
above) or globally with `RequireAuthentication`, the same `@Middleware`
vocabulary the previous exercise covered:

```swift
container.pipeline {
    RequireAuthentication.self
}
```

`RequireAuthentication` isn't installed by `FlightSecurityModule` itself —
it's a policy decision the application makes, not something a security
module should assume for you. It composes with `Authentication` the same
way any two middleware do: `FlightSecurityModule.configure` runs (and
registers `Authentication`) before `AppModule.configure`'s own
`pipeline { }` call, because that's the order the bootstrap's `modules:`
list named them in — so `RequireAuthentication` always sees the principal
this request's `Authentication` decided, with no order number to get right
by hand.

Answering a request `RequireAuthentication` rejects always carries an RFC
6750 `WWW-Authenticate: Bearer` challenge; `SecurityError.unauthenticated`
and `.forbidden` thrown from a handler render as the generic 401/403
either way.
