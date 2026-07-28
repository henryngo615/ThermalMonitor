// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThermalMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CSensors",
            path: "Sources/CSensors",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "ThermalMonitor",
            dependencies: ["CSensors"],
            path: "Sources/ThermalMonitor"
        )
    ]
)
