// swift-tools-version: 6.1
import PackageDescription

// Whisp depends on the in-tree Moonshine Swift package at ../moonshine/swift.
// Run `scripts/bootstrap.sh` once to build Moonshine.xcframework before
// `swift build` / `swift test` will resolve.
let package = Package(
    name: "Whisp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WhispCore", targets: ["WhispCore"]),
        .executable(name: "Whisp", targets: ["Whisp"]),
    ],
    dependencies: [
        .package(name: "Moonshine", path: "../moonshine/swift"),
    ],
    targets: [
        .target(
            name: "WhispCore",
            path: "Sources/WhispCore"
        ),
        .executableTarget(
            name: "Whisp",
            dependencies: [
                "WhispCore",
                .product(name: "MoonshineVoice", package: "Moonshine"),
            ],
            path: "Sources/Whisp",
            exclude: [
                "Resources/Info.plist",
                "Resources/Whisp.entitlements",
                // Models are downloaded into Resources/models/ by
                // scripts/download-models.sh and copied straight into
                // Contents/Resources/models/ by scripts/build-release.sh.
                // We exclude them from SwiftPM so it doesn't bundle them
                // into the Whisp_Whisp.bundle and produce 'unhandled file'
                // warnings on every build.
                "Resources/models",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "WhispCoreTests",
            dependencies: ["WhispCore"],
            path: "Tests/WhispCoreTests"
        ),
        .testTarget(
            name: "WhispIntegrationTests",
            dependencies: [
                "WhispCore",
                .product(name: "MoonshineVoice", package: "Moonshine"),
            ],
            path: "Tests/WhispIntegrationTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
