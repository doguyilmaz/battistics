// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BattisticsCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BattisticsCore", targets: ["BattisticsCore"]),
        .executable(name: "battistics-mcp", targets: ["BattisticsMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .target(
            name: "BattisticsCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "BattisticsMCP",
            dependencies: ["BattisticsCore", .product(name: "MCP", package: "swift-sdk")]
        ),
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
