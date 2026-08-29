import FlightCore
import FlightPubSub
import FlightWeb
import Foundation

@Controller
struct ActivityController {
    @GetMapping("/events")
    func events(_ context: RequestContext) -> Response {
        .serverSentEvents { events in
            events.send(data: "hello", event: "greeting")
        }
    }

    @GetMapping("/activity")
    func activity(_ context: RequestContext) throws -> Response {
        let pubsub = try context.resolve((any PubSub).self)
        return .serverSentEvents { events in
            for await message in pubsub.subscribe("activity") {
                let line = String(decoding: message.payload, as: UTF8.self)
                guard events.send(data: line, event: "activity") else {
                    return  // client went away; the subscription tears down with us
                }
            }
        }
    }
}
