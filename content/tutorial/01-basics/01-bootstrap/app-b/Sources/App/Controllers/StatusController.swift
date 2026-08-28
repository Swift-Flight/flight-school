import FlightCore
import FlightWeb

@Controller
struct StatusController {
    @ConfigValue("app.name") var appName: String

    @GetMapping("/status")
    func status(_ context: RequestContext) -> String {
        "\(appName): up"
    }
}
