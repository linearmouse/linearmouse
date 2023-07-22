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
    dependencies: [
        .package(name: "ObservationToken", path: "../ObservationToken")
    ],
    targets: [
        .target(
            name: "PointerKitC",
            dependencies: []
        ),
        .target(
            name: "PointerKit",
            dependencies: [
                "ObservationToken",
                "PointerKitC"
            ]
        ),
        .testTarget(
            name: "PointerKitTests",
            dependencies: ["PointerKit"]
        )
    ]
)
