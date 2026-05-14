// swift-tools-version: 6.1
import PackageDescription

// Stand-alone Swift package for OpenWisprCore — the pure-Foundation
// logic layer (state machines, transcript buffer, etc.).
//
// Lives in its own Package.swift specifically so that CI can build and
// test it without pulling in the Moonshine dependency required by the
// root OpenWispr package. The root Package.swift consumes this package
// via a local-path dependency.
let package = Package(
    name: "OpenWisprCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenWisprCore", targets: ["OpenWisprCore"]),
    ],
    targets: [
        .target(
            name: "OpenWisprCore",
            path: "Sources/OpenWisprCore"
        ),
        .testTarget(
            name: "OpenWisprCoreTests",
            dependencies: ["OpenWisprCore"],
            path: "Tests/OpenWisprCoreTests"
        ),
    ]
)
