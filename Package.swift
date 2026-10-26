// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TabWindo",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "TabWindo",
            path: "Sources/TabWindo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TabWindoTests",
            dependencies: ["TabWindo"],
            path: "Tests/TabWindoTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
