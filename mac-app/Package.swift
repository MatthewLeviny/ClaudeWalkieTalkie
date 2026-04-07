// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClaudeMulti",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "ClaudeMultiLib",
            path: "Sources/ClaudeMulti",
            exclude: ["Resources/Info.plist", "App/ClaudeMultiApp.swift"]
        ),
        .executableTarget(
            name: "ClaudeMulti",
            dependencies: ["ClaudeMultiLib"],
            path: "Sources/ClaudeMultiApp"
        ),
        .testTarget(
            name: "ClaudeMultiTests",
            dependencies: ["ClaudeMultiLib"],
            path: "Tests/ClaudeMultiTests"
        )
    ]
)
