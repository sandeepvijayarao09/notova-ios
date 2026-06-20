// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Keychain",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Keychain", targets: ["Keychain"])
    ],
    targets: [
        .target(
            name: "Keychain",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "KeychainTests",
            dependencies: ["Keychain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
