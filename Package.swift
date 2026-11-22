// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ByeSlides",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "ByeSlides", resources: [.copy("Resources")]),
        .testTarget(name: "ByeSlidesTests", dependencies: ["ByeSlides"]),
    ]
)
