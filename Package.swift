// swift-tools-version:5.9
import PackageDescription

// Noelify is split into two targets:
//  - NoelifyCore: platform-independent logic (settings, wallpaper backup/restore,
//    Christmas Mode coordination). Foundation only, fully unit-tested.
//  - Noelify: the native macOS menu bar app (SwiftUI + AppKit).
//
// Build the runnable .app bundle with `scripts/build-app.sh`.
let package = Package(
    name: "Noelify",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Noelify", targets: ["Noelify"]),
    ],
    targets: [
        .target(name: "NoelifyCore"),
        .executableTarget(
            name: "Noelify",
            dependencies: ["NoelifyCore"]
        ),
        .testTarget(
            name: "NoelifyCoreTests",
            dependencies: ["NoelifyCore"]
        ),
    ]
)
