import FlightCore
import FlightWeb

struct Greeting: Codable, ResponseEncodable {
    let message: String
}

@Controller
struct GreetingController {
    @GetMapping("/hello")
    func hello(_ context: RequestContext) -> String {
        "hello, flight"
    }

    @GetMapping("/hello-json")
    func helloJSON(_ context: RequestContext) -> Greeting {
        Greeting(message: "hello, flight")
    }
}
