// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KeyKit",
    products: [
        .library(
            name: "KeyKit",
            targets: ["KeyKit"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "KeyKitC",
            dependencies: []
        ),
        .target(
            name: "KeyKit",
            dependencies: ["KeyKitC"]
        ),
        .testTarget(
            name: "KeyKitTests",
            dependencies: ["KeyKit"]
        )
    ]
)
