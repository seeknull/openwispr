// swift-tools-version: 6.1
import PackageDescription

// OpenWispr depends on:
//   - the in-tree Moonshine Swift package at ../moonshine/swift
//     (run `scripts/bootstrap.sh` once to build Moonshine.xcframework
//     before `swift build` / `swift test` will resolve)
//   - the OpenWisprCore sub-package at ./Core, which lives in its own
//     Package.swift so it can be tested without pulling Moonshine
//     (used by CI; see .github/workflows/ci.yml)
let package = Package(
    name: "OpenWispr",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenWispr", targets: ["OpenWispr"]),
    ],
    dependencies: [
        .package(name: "OpenWisprCore", path: "Core"),
        .package(name: "Moonshine", path: "../moonshine/swift"),
    ],
    targets: [
        .executableTarget(
            name: "OpenWispr",
            dependencies: [
                .product(name: "OpenWisprCore", package: "OpenWisprCore"),
                .product(name: "MoonshineVoice", package: "Moonshine"),
            ],
            path: "Sources/OpenWispr",
            exclude: [
                "Resources/Info.plist",
                "Resources/OpenWispr.entitlements",
                // Models are downloaded into Resources/models/ by
                // scripts/download-models.sh and copied straight into
                // Contents/Resources/models/ by scripts/build-release.sh.
                // We exclude them from SwiftPM so it doesn't bundle them
                // into the OpenWispr_OpenWispr.bundle and produce
                // 'unhandled file' warnings on every build.
                "Resources/models",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "OpenWisprIntegrationTests",
            dependencies: [
                .product(name: "OpenWisprCore", package: "OpenWisprCore"),
                .product(name: "MoonshineVoice", package: "Moonshine"),
            ],
            path: "Tests/OpenWisprIntegrationTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
