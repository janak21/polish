// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Polish",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(name: "Polish", dependencies: ["KeyboardShortcuts"]),
        .testTarget(name: "PolishTests", dependencies: ["Polish"]),
    ]
)
