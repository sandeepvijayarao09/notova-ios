// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AudioCapture",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AudioCapture", targets: ["AudioCapture"])
    ],
    dependencies: [
        .package(path: "../NotovaCore")
    ],
    targets: [
        .target(
            name: "AudioCapture",
            dependencies: ["NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: ["AudioCapture", "NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
