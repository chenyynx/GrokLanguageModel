// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "GrokLanguageModel",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
        .visionOS("27.0"),
    ],
    products: [
        .library(name: "GrokLanguageModel", targets: ["GrokLanguageModel"]),
    ],
    targets: [
        .target(
            name: "GrokLanguageModel",
            path: "GrokLanguageModel",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "GrokLanguageModelTests",
            dependencies: ["GrokLanguageModel"],
            path: "GrokLanguageModelTests",
            swiftSettings: swiftSettings
        ),
    ]
)
