// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "MacStart",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "MacStart", targets: ["MacStart"])
    ],
    targets: [
        .target(name: "MacStartCore"),
        .executableTarget(
            name: "MacStart",
            dependencies: ["MacStartCore"]
        ),
        .testTarget(
            name: "MacStartCoreTests",
            dependencies: ["MacStartCore"]
        ),
    ]
)
