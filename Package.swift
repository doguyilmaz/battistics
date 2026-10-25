// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BattisticsCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BattisticsCore", targets: ["BattisticsCore"]),
        .library(name: "BattisticsRemote", targets: ["BattisticsRemote"]),
        .executable(name: "battistics", targets: ["BattisticsCLI"]),
        .executable(name: "battistics-mcp", targets: ["BattisticsMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")
    ],
    targets: [
        .executableTarget(name: "BattisticsCLI", dependencies: ["BattisticsCore"]),
        .testTarget(name: "BattisticsCLITests", dependencies: ["BattisticsCLI", "BattisticsCore"]),
        .target(
            name: "BattisticsCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "BattisticsMCP",
            dependencies: ["BattisticsCore", .product(name: "MCP", package: "swift-sdk")]
        ),
        .target(name: "BattisticsRemote"),
        .testTarget(name: "BattisticsRemoteTests", dependencies: ["BattisticsRemote"]),
        .testTarget(
            name: "BattisticsCoreTests",
            dependencies: ["BattisticsCore"]
        ),
        .testTarget(
            name: "BattisticsMCPTests",
            dependencies: ["BattisticsMCP", "BattisticsCore", .product(name: "MCP", package: "swift-sdk")]
        ),
    ]
)
