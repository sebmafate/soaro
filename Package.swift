// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Soaro",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Mises à jour automatiques (voir docs/updates.md).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Soaro",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Soaro",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SoaroTests",
            dependencies: ["Soaro"],
            path: "Tests/SoaroTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
