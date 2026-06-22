// swift-tools-version:5.9
import PackageDescription

// PressF4 is built as a sandboxed .app via the top-level Makefile (swiftc directly),
// not through SwiftPM. This manifest exists only so the pure model logic can be
// exercised by XCTest via `swift test`. The library target deliberately includes
// just `Sources/Models/` — everything else (Services, Views, App.swift) needs
// AppKit/ScreenCaptureKit and is kept out of the SwiftPM module.
let package = Package(
    name: "PressF4",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PressF4Core", targets: ["PressF4Core"]),
    ],
    targets: [
        .target(
            name: "PressF4Core",
            path: "Sources/Models"
        ),
        .testTarget(
            name: "PressF4CoreTests",
            dependencies: ["PressF4Core"],
            path: "Tests/PressF4CoreTests"
        ),
    ]
)
