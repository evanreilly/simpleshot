// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SimpleShot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SimpleShot", targets: ["SimpleShot"])
    ],
    targets: [
        .executableTarget(
            name: "SimpleShot",
            path: "Sources/SimpleShot"
        ),
        .testTarget(
            name: "SimpleShotTests",
            dependencies: ["SimpleShot"],
            path: "Tests/SimpleShotTests"
        )
    ]
)
