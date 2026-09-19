// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Utter",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Utter", targets: ["Utter"]),
        .library(name: "UtterCore", targets: ["UtterCore"]),
        .executable(name: "utter-test-runner", targets: ["UtterTests"]),
        .executable(name: "UtterModelCheck", targets: ["UtterModelCheck"]),
        .executable(name: "UtterRenderPreview", targets: ["UtterRenderPreview"]),
    ],
    dependencies: [
        .package(path: "Packages/FluidAudio"),
    ],
    targets: [
        .target(
            name: "UtterCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/UtterCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "Utter",
            dependencies: ["UtterCore"],
            path: "Sources/Utter",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "UtterModelCheck",
            dependencies: ["UtterCore", .product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/UtterModelCheck",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "UtterTests",
            dependencies: ["UtterCore"],
            path: "Tests/UtterTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "UtterRenderPreview",
            dependencies: ["UtterCore"],
            path: "Sources/UtterRenderPreview",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
