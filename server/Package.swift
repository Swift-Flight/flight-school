// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "server",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/Swift-Flight/flight.git", from: "0.8.0", traits: ["Web"]),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0")
    ],
    targets: [
        .executableTarget(
            name: "Server",
            dependencies: [
                .product(name: "FlightCore", package: "flight"),
                .product(name: "FlightWeb", package: "flight"),
                .product(name: "FlightTransport", package: "flight"),
                .product(name: "FlightChannels", package: "flight"),
                .product(name: "AsyncHTTPClient", package: "async-http-client")
            ],
            plugins: [.plugin(name: "FlightRegistrationPlugin", package: "flight")]
        )
    ]
)
