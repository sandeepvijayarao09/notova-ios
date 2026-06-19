// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Transcription",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Transcription", targets: ["Transcription"])
    ],
    dependencies: [
        .package(path: "../NotovaCore")
    ],
    targets: [
        .target(
            name: "Transcription",
            dependencies: ["NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TranscriptionTests",
            dependencies: ["Transcription", "NotovaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
