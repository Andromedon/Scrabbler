// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScrabblerKit",
    defaultLocalization: "pl",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ScrabblerKit", targets: ["ScrabblerKit"])
    ],
    targets: [
        .target(
            name: "ScrabblerKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ScrabblerKitTests",
            dependencies: ["ScrabblerKit"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
