// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PointerKit",
    products: [
        .library(
            name: "PointerKit",
            targets: ["PointerKit"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PointerKitC",
            dependencies: []
        ),
        .target(
            name: "PointerKit",
            dependencies: ["PointerKitC"]
        ),
        .testTarget(
            name: "PointerKitTests",
            dependencies: ["PointerKit"]
        )
    ]
)
