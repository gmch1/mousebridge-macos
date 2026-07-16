// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseBridge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MouseBridge", targets: ["MouseBridge"]),
    ],
    targets: [
        .systemLibrary(
            name: "MultitouchSupport",
            path: "Sources/MultitouchSupport"
        ),
        .executableTarget(
            name: "MouseBridge",
            dependencies: ["MultitouchSupport"],
            path: "Sources/MouseBridge",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("MultitouchSupport"),
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
            ]
        ),
        .testTarget(
            name: "MouseBridgeTests",
            dependencies: ["MouseBridge"],
            path: "Tests/MouseBridgeTests"
        ),
    ]
)
