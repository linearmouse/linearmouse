// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PointerKit",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "PointerKit",
            targets: ["PointerKit"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
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
