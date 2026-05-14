# Building OpenWispr

## Prerequisites

- **macOS 13+** (OpenWispr's deployment target; you can develop on newer
  versions).
- **Xcode 15+**, or the matching Command Line Tools — OpenWispr uses Swift
  6.1.
- **CMake 3.22+** — `brew install cmake`. Only needed once, to build
  Moonshine's XCFramework.
- A clone of [moonshine](https://github.com/moonshine-ai/moonshine) as a
  sibling of your `openwispr` checkout (see [README.md](../README.md#build-from-source)).

## Bootstrap

```bash
cd openwispr
./scripts/bootstrap.sh
```

This script:

1. Verifies `../moonshine` exists.
2. Runs `../moonshine/scripts/build-swift.sh` to produce
   `Moonshine.xcframework` (iOS, iOS-simulator, macOS slices). This is
   the artifact `Package.swift` depends on. Takes ~3 minutes on Apple
   Silicon.
3. Runs `swift package resolve` so OpenWispr's deps are cached.

You only need to re-run `bootstrap.sh` if Moonshine's core C++ changes
or you blow away `../moonshine/swift/Moonshine.xcframework`.

## Build & run

```bash
swift build                # debug build, x86_64 or arm64 depending on host
swift run OpenWispr            # launch the menu-bar app
```

The first `swift run` after bootstrap takes a minute to compile
MoonshineVoice. Subsequent runs are incremental.

## Tests

```bash
swift test                              # everything
swift test --filter OpenWisprCoreTests      # pure logic, fast
swift test --filter OpenWisprIntegrationTests
```

`OpenWisprIntegrationTests` loads Moonshine's bundled tiny-en model and a
WAV fixture; it confirms the xcframework links and the transcription
pipeline produces sensible output.

## Building the release .app

```bash
./scripts/download-models.sh        # fetch medium-streaming-en (~280 MB)
./scripts/build-release.sh
```

Output:

```
build/OpenWispr.app
dist/OpenWispr-<version>.zip
```

The release script builds a universal (arm64 + x86_64) binary, assembles
the .app bundle by hand, copies the model into `Contents/Resources/models/`,
and zips the result for distribution.

The build is **not signed or notarized** — see
[distribution.md](distribution.md) for the Gatekeeper handshake users
have to do on first launch.

## Common issues

### `error: missing package product 'MoonshineVoice'`

You haven't run `scripts/bootstrap.sh` yet. The local Swift package at
`../moonshine/swift` declares a `binaryTarget` that requires
`Moonshine.xcframework`, which is **not** checked in. The bootstrap
script generates it.

### `error: could not find Moonshine repo at ...`

OpenWispr expects `moonshine/` as a sibling of `openwispr/`. If you have it
elsewhere, either symlink it or edit the path in `Package.swift` and
`scripts/bootstrap.sh`.

### `swift test` fails with `dyld: Library not loaded: ...libonnxruntime...`

The Moonshine XCFramework includes a static onnxruntime; this usually
means an older partial build is on disk. Nuke and rebuild:

```bash
rm -rf ../moonshine/swift/Moonshine.xcframework ../moonshine/core/build
./scripts/bootstrap.sh
```

### OpenWispr launches but the menu-bar icon doesn't appear

`Info.plist` sets `LSUIElement = true`, which makes OpenWispr an agent
(no Dock icon). The icon will be in the menu bar — look for the
waveform glyph on the right side. If it's truly missing, check
Console.app for `subsystem:dev.openwispr.app` log lines.
