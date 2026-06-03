// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThermalMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CSMC",
            path: "Sources/CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "ThermalMonitor",
            dependencies: ["CSMC"],
            path: "Sources/ThermalMonitor",
        )
    ]
)
