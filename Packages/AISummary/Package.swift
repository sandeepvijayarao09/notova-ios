// swift-tools-version:6.0
import PackageDescription
import Foundation

// MLX (local Gemma) is heavy, Metal-only, and fetched from the network. It is
// opt-in via the NOTOVA_ENABLE_MLX environment variable so the default build —
// simulator, CI, offline — never fetches or links it and stays green. A device
// build that wants real local Gemma sets NOTOVA_ENABLE_MLX=1 before generating.
let mlxEnabled = ProcessInfo.processInfo.environment["NOTOVA_ENABLE_MLX"] == "1"

var dependencies: [Package.Dependency] = [
    .package(path: "../NotovaCore"),
    .package(path: "../ModelManagement")
]

var targetDependencies: [Target.Dependency] = [
    "NotovaCore",
    "ModelManagement"
]

var swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

if mlxEnabled {
    dependencies.append(
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.21.2")
    )
    targetDependencies.append(contentsOf: [
        .product(name: "MLXLLM", package: "mlx-swift-examples"),
        .product(name: "MLXLMCommon", package: "mlx-swift-examples")
    ])
    swiftSettings.append(.define("NOTOVA_ENABLE_MLX"))
}

let package = Package(
    name: "AISummary",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AISummary", targets: ["AISummary"])
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "AISummary",
            dependencies: targetDependencies,
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AISummaryTests",
            dependencies: ["AISummary", "NotovaCore", "ModelManagement"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
