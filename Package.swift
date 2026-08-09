// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BattisticsCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BattisticsCore", targets: ["BattisticsCore"])
    ],
    targets: [
        .target(
            name: "BattisticsCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "BattisticsCoreTests",
            dependencies: ["BattisticsCore"]
        ),
    ]
)
