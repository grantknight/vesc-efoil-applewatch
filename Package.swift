// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VESCCore",
    products: [.library(name: "VESCCore", targets: ["VESCCore"])],
    targets: [
        .target(name: "VESCCore", path: "MyWatchOSApp Watch App",
                sources: ["Packet.swift", "VByteArray.swift", "VescTelemetryDecoder.swift", "RideModels.swift", "RideStore.swift", "TelemetrySnapshot.swift", "VescRequestQueue.swift"]),
        .testTarget(name: "VESCCoreTests", dependencies: ["VESCCore"], path: "Tests/VESCCoreTests")
    ]
)
