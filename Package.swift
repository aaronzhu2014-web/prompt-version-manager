// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PromptVersionManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PromptVersionCore", targets: ["PromptVersionCore"]),
        .executable(name: "PromptVersionManager", targets: ["PromptVersionManager"]),
        .executable(name: "PromptVersionCoreChecks", targets: ["PromptVersionCoreChecks"]),
    ],
    targets: [
        .target(
            name: "PromptVersionCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "PromptVersionManager",
            dependencies: ["PromptVersionCore"]
        ),
        .executableTarget(
            name: "PromptVersionCoreChecks",
            dependencies: ["PromptVersionCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
