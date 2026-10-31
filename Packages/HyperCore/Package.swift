// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HyperCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "HyperCore", targets: ["HyperCore"])],
    targets: [
        .target(
            name: "HyperCore",
            resources: [.copy("Resources/palettes.json"), .process("Resources/Localizable.xcstrings")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HyperCoreTests",
            dependencies: ["HyperCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
