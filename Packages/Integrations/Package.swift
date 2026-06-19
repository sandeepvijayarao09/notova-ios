// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Integrations",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Integrations", targets: ["Integrations"])
    ],
    dependencies: [
        .package(path: "../NotovaCore")
    ],
    targets: [
        .target(
            name: "Integrations",
            dependencies: ["NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "IntegrationsTests",
            dependencies: ["Integrations", "NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
