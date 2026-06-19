// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../NotovaCore")
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: ["NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
