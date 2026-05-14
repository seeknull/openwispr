// swift-tools-version: 6.1
import PackageDescription

// OpenWispr depends on the in-tree Moonshine Swift package at ../moonshine/swift.
// Run `scripts/bootstrap.sh` once to build Moonshine.xcframework before
// `swift build` / `swift test` will resolve.
let package = Package(
    name: "OpenWispr",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenWisprCore", targets: ["OpenWisprCore"]),
        .executable(name: "OpenWispr", targets: ["OpenWispr"]),
    ],
    dependencies: [
        .package(name: "Moonshine", path: "../moonshine/swift"),
    ],
    targets: [
        .target(
            name: "OpenWisprCore",
            path: "Sources/OpenWisprCore"
        ),
        .executableTarget(
            name: "OpenWispr",
            dependencies: [
                "OpenWisprCore",
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
                // into the OpenWispr_OpenWispr.bundle and produce 'unhandled file'
                // warnings on every build.
                "Resources/models",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "OpenWisprCoreTests",
            dependencies: ["OpenWisprCore"],
            path: "Tests/OpenWisprCoreTests"
        ),
        .testTarget(
            name: "OpenWisprIntegrationTests",
            dependencies: [
                "OpenWisprCore",
                .product(name: "MoonshineVoice", package: "Moonshine"),
            ],
            path: "Tests/OpenWisprIntegrationTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
