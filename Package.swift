// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseBridge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MouseBridge", targets: ["MouseBridge"]),
    ],
    targets: [
        .executableTarget(
            name: "MouseBridge",
            path: "Sources/MouseBridge",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MouseBridgeTests",
            dependencies: ["MouseBridge"],
            path: "Tests/MouseBridgeTests"
        ),
    ]
)
