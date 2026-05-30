// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PTK",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PTKCore", targets: ["PTKCore"]),
        .executable(name: "PTK", targets: ["PTKApp"])
    ],
    targets: [
        .target(name: "PTKCore"),
        .executableTarget(
            name: "PTKApp",
            dependencies: ["PTKCore"]
        ),
        .testTarget(
            name: "PTKCoreTests",
            dependencies: ["PTKCore"]
        ),
        .testTarget(
            name: "PTKAppTests",
            dependencies: ["PTKApp", "PTKCore"]
        )
    ]
)
