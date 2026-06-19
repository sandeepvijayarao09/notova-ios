// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotovaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotovaCore", targets: ["NotovaCore"])
    ],
    targets: [
        .target(
            name: "NotovaCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "NotovaCoreTests",
            dependencies: ["NotovaCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
