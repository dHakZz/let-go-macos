// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LetGo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LetGoCore", targets: ["LetGoCore"]),
        .executable(name: "LetGoApp", targets: ["LetGoApp"])
    ],
    targets: [
        .target(
            name: "LetGoCore"
        ),
        .executableTarget(
            name: "LetGoApp",
            dependencies: ["LetGoCore"]
        ),
        .testTarget(
            name: "LetGoCoreTests",
            dependencies: ["LetGoCore"]
        )
    ]
)
