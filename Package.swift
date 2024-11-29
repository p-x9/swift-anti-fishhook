// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AntiFishHook",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "AntiFishHook",
            targets: ["AntiFishHook"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/p-x9/swift-fishhook.git", from: "0.5.0"),
        .package(url: "https://github.com/p-x9/MachOKit.git", from: "0.25.0")
    ],
    targets: [
        .target(
            name: "AntiFishHook",
            dependencies: [
                .product(name: "FishHook", package: "swift-fishhook"),
                .product(name: "MachOKit", package: "MachOKit")
            ]
        ),
        .testTarget(
            name: "AntiFishHookTests",
            dependencies: ["AntiFishHook"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker",
                    "-interposable"
                ])
            ]
        ),
    ]
)
