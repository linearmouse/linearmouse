// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "HIDPP",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "HIDPP",
            targets: ["HIDPP"]
        )
    ],
    targets: [
        .target(name: "HIDPP"),
        .testTarget(
            name: "HIDPPTests",
            dependencies: ["HIDPP"]
        )
    ]
)
