// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Accalmie",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Accalmie",
            path: "Sources/Accalmie",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AccalmieTests",
            dependencies: ["Accalmie"],
            path: "Tests/AccalmieTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
