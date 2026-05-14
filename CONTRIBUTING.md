# Contributing to Whisp

Thanks for taking the time! Whisp is small and the codebase is friendly —
this guide should get you from clone to first PR in under 30 minutes.

## Prereqs

- macOS 13+ (the deployment target — newer is fine).
- **Xcode 15+** for the Swift 6.1 toolchain.
- **CMake** (needed once to build Moonshine's XCFramework). `brew install cmake`.
- A clone of [moonshine](https://github.com/moonshine-ai/moonshine) as a
  sibling directory to your `whisp` checkout.

```
workspace/
├── moonshine/
└── whisp/      # you are here
```

## First-time setup

```bash
cd whisp
./scripts/bootstrap.sh        # builds Moonshine.xcframework once (~3 min)
swift test --filter WhispCoreTests
```

If `WhispCoreTests` passes, your toolchain is good. If not, see
[docs/building.md](docs/building.md).

## Dev loop

```bash
swift run Whisp               # launch the menu-bar app
swift test                    # full suite
swift test --filter WhispCoreTests   # fast iteration on pure logic
```

For UI work, open `Package.swift` in Xcode (Xcode treats it like an
`.xcodeproj`). Schemes are generated automatically.

## Code style

- Swift 6.1, strict concurrency where possible. Most app-level types are
  `@MainActor`.
- Pure-logic types live in `WhispCore` and must not import AppKit /
  CoreGraphics / AVFoundation. If a piece of code is testable without UI,
  put it in `WhispCore` and write a unit test.
- Comments explain **why**, not **what**. Don't restate the code.

## Tests

Every PR should keep `WhispCoreTests` green. New behavior in
`WhispCore` needs a unit test; new behavior in the app layer is
welcome but optional (UI is hard to test deterministically).

If you change the dictation flow, ensure `WhispIntegrationTests` still
passes — it loads the Moonshine model and runs a WAV through it.

## Filing issues

- For bugs, include macOS version (`sw_vers`), Whisp version, and what
  permission grants you've completed.
- For feature requests, please describe the user-visible behavior, not the
  implementation.

## License

By contributing, you agree your contributions are licensed under the
project's MIT license.
