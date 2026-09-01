import FlightCore
import FlightWeb

@Controller
struct StatusController {
    @ConfigValue("app.name") var appName: String

    @GetRoute("/status")
    func status(_ context: RequestContext) -> String {
        "\(appName): up"
    }
}
