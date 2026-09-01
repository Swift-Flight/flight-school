import FlightCore
import FlightWeb

struct Greeting: Codable, ResponseEncodable {
    let message: String
}

@Controller
struct GreetingController {
    @GetRoute("/hello")
    func hello(_ context: RequestContext) -> String {
        "hello, flight"
    }

    @GetRoute("/hello-json")
    func helloJSON(_ context: RequestContext) -> Greeting {
        Greeting(message: "hello, flight")
    }
}
