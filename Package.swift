// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Music",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LeoMusic", targets: ["JarvisMusic"])
    ],
    targets: [
        .executableTarget(
            name: "JarvisMusic",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("Network"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "JarvisMusicTests",
            dependencies: ["JarvisMusic"]
        )
    ]
)
