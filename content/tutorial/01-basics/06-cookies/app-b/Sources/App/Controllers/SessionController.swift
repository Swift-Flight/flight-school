import FlightCore
import FlightWeb
import Foundation

struct LoginForm: Decodable {
    let name: String
}

@Controller
struct SessionController {
    @PostMapping("/login")
    func logIn(_ context: RequestContext, body: LoginForm) -> Response {
        Response.seeOther("/me")
            .settingCookie(
                Cookie(name: "who", value: body.name, maxAge: .seconds(3600)))
    }

    @GetMapping("/me")
    func me(_ context: RequestContext) -> String {
        guard let who = context.request.cookie("who") else {
            return "not logged in"
        }
        return "hello, \(who)"
    }

    @PostMapping("/logout")
    func logOut(_ context: RequestContext) -> Response {
        Response.seeOther("/me")
            .settingCookie(Cookie(name: "who", value: "", maxAge: .seconds(0)))
    }
}
