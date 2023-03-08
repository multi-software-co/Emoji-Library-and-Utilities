// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "EmojiUtilities",
    platforms: [.macOS(.v10_14)],
    products: [
        .library(
            name: "EmojiUtilities",
            targets: ["EmojiUtilities"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "EmojiUtilities",
            dependencies: [],
            resources: [
                .process("Generated")
            ]),
        .executableTarget(
            name: "GenerateEmoji",
            dependencies: [
            "EmojiUtilities"
            ]),
        // .testTarget(
        //     name: "EmojiUtilitiesTests",
        //     dependencies: ["EmojiUtilities"]),
        // .testTarget(
        //     name: "GenerateEmojiTests",
        //     dependencies: ["GenerateEmoji"]),
    ]
)
