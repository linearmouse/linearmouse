// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ObservationToken",
    products: [
        .library(
            name: "ObservationToken",
            targets: ["ObservationToken"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ObservationToken",
            dependencies: []
        ),
        .testTarget(
            name: "ObservationTokenTests",
            dependencies: ["ObservationToken"]
        )
    ]
)
