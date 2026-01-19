// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenBW-iOS",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "OpenBW",
            targets: ["OpenBW"]),
    ],
    targets: [
        // Swift wrapper around the Objective-C++ bridge
        .target(
            name: "OpenBW",
            dependencies: ["OpenBWBridge"],
            path: "Sources/StarCraftApp"
        ),
        // Objective-C++ bridge (binary target would link pre-built libraries)
        .target(
            name: "OpenBWBridge",
            path: "Sources/OpenBWBridge",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../../openbw"),
                .define("ASIO_STANDALONE"),
                .define("ASIO_NO_DEPRECATED"),
                .define("OPENBW_HEADLESS", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx14
)
