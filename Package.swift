// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WormholeLink",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "WormholeLink",
            targets: ["WormholeLink"]
        )
    ],
    targets: [
        .executableTarget(
            name: "WormholeLink",
            path: "Sources/WormholeLink"
        )
    ]
)