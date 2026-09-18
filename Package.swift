// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VTT",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "VTT", targets: ["VTT"]),
        .library(name: "VTTCore", targets: ["VTTCore"]),
        .executable(name: "vtt-test-runner", targets: ["VTTTests"]),
        .executable(name: "VTTModelCheck", targets: ["VTTModelCheck"]),
        .executable(name: "VTTRenderPreview", targets: ["VTTRenderPreview"]),
    ],
    dependencies: [
        .package(path: "Packages/FluidAudio"),
    ],
    targets: [
        .target(
            name: "VTTCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VTTCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "VTT",
            dependencies: ["VTTCore"],
            path: "Sources/VTT",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "VTTModelCheck",
            dependencies: ["VTTCore", .product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/VTTModelCheck",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "VTTTests",
            dependencies: ["VTTCore"],
            path: "Tests/VTTTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "VTTRenderPreview",
            dependencies: ["VTTCore"],
            path: "Sources/VTTRenderPreview",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
