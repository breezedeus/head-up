// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadUp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HeadUp", targets: ["HeadUp"])
    ],
    targets: [
        .executableTarget(
            name: "HeadUp",
            path: "Sources/HeadUp"
        ),
        .testTarget(
            name: "HeadUpTests",
            dependencies: ["HeadUp"],
            path: "Tests/HeadUpTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
