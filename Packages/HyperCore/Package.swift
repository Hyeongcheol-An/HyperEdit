// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HyperCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "HyperCore", targets: ["HyperCore"])],
    dependencies: [
        // 마크다운 미리보기 렌더러 (Apache-2.0). GFM 표·취소선·체크리스트를 cmark-gfm 으로 파싱한다.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "HyperCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            resources: [.copy("Resources/palettes.json"), .copy("Resources/Welcome"), .process("Resources/Localizable.xcstrings")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HyperCoreTests",
            dependencies: ["HyperCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
