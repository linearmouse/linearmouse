// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DockKit",
    products: [
        .library(
            name: "DockKit",
            targets: ["DockKit"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "DockKitC",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        ),
        .target(
            name: "DockKit",
            dependencies: ["DockKitC"]
        ),
        .testTarget(
            name: "DockKitTests",
            dependencies: ["DockKit"]
        )
    ]
)
