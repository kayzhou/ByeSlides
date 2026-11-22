// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ByeSlides",
    platforms: [.macOS(.v26)],
    targets: [
        // Shared by the app and the Quick Look extension: file decoding and the reading page.
        .target(name: "ByeSlidesCore", resources: [.copy("Resources")]),
        .executableTarget(name: "ByeSlides", dependencies: ["ByeSlidesCore"]),
        // Linked like an app extension; Scripts/build-app.sh wraps the binary in an .appex bundle.
        .executableTarget(
            name: "ByeSlidesQuickLook",
            dependencies: ["ByeSlidesCore"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(name: "ByeSlidesTests", dependencies: ["ByeSlides", "ByeSlidesCore"]),
    ]
)
