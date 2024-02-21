// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AntiFishHook",
    products: [
        .library(
            name: "AntiFishHook",
            targets: ["AntiFishHook"]
        ),
    ],
    targets: [
        .target(
            name: "AntiFishHook"
        ),
        .testTarget(
            name: "AntiFishHookTests",
            dependencies: ["AntiFishHook"]
        ),
    ]
)
