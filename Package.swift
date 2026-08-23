// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WastlyKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "WastlyKit", targets: ["WastlyKit"]),
    ],
    targets: [
        .target(
            name: "WastlyKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "WastlyKitTests",
            dependencies: ["WastlyKit"]
        ),
    ]
)
