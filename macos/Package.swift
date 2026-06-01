// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PTK",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PTKCore", targets: ["PTKCore"]),
        .executable(name: "PTK", targets: ["PTK"])
    ],
    targets: [
        .target(name: "PTKCore"),
        .target(
            name: "PTKApp",
            dependencies: ["PTKCore"]
        ),
        .executableTarget(
            name: "PTK",
            dependencies: ["PTKApp"]
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
