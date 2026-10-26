// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "spokenlog_audio",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0"),
    ],
    products: [
        .library(name: "spokenlog-audio", targets: ["spokenlog_audio"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "spokenlog_audio",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
