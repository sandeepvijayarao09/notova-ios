// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ModelManagement",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ModelManagement", targets: ["ModelManagement"])
    ],
    dependencies: [
        .package(path: "../NotovaCore")
    ],
    targets: [
        .target(
            name: "ModelManagement",
            dependencies: ["NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ModelManagementTests",
            dependencies: ["ModelManagement", "NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
