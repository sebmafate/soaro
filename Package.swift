// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Soaro",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Soaro",
            path: "Sources/Soaro",
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
