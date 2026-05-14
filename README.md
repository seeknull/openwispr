# Whisp

**Open-source dictation for macOS, powered by [Moonshine](https://moonshine.ai).**

Whisp is a tiny menu-bar app that lets you dictate into _any_ macOS app —
your editor, your terminal, Slack, a search bar, anywhere your cursor is.
It runs fully on-device, uses no cloud services, and ships under the MIT
license.

- ✏️ **Type anywhere with your voice.** Press the hotkey, talk, press again
  to stop. Transcript flows into the focused app.
- 🔒 **Fully offline.** No network calls, no API keys. The Moonshine
  speech-to-text model runs on your CPU.
- 🪶 **Lightweight.** Pure Swift, no Electron, no Python runtime. The .app
  is ~300 MB (most of which is the model).
- 🎛 **Tweakable insertion.** Clipboard paste (fast, works everywhere) or
  synthesized keystrokes (no clipboard interference).
- ⌨️ **Fn+Option to toggle**, by default. Configurable.

## Status

Pre-release (v0.1.0). The core dictation loop works end-to-end on macOS 13+.
Hotkey rebinding, launch-at-login, and notarized distribution are on the
roadmap (see [docs/roadmap.md](docs/roadmap.md)).

## How it works

```
┌─────────────────────────┐
│  Fn + Option pressed    │
│  (CGEventTap)           │
└────────────┬────────────┘
             ▼
┌─────────────────────────┐         ┌───────────────────────────┐
│  HotkeyStateMachine     │────────▶│  DictationEngine          │
│  (WhispCore, testable)  │         │  ↳ MicTranscriber         │
└─────────────────────────┘         │     (MoonshineVoice)      │
                                    └──────────────┬────────────┘
                                                   ▼
                                    ┌───────────────────────────┐
                                    │  TranscriptBuffer         │
                                    │  (per-line, trimmed)      │
                                    └──────────────┬────────────┘
                                                   ▼
                                    ┌───────────────────────────┐
                                    │  TextInjector             │
                                    │  ↳ clipboard paste OR     │
                                    │    synthetic keystrokes   │
                                    └───────────────────────────┘
```

Hardened by:

- `WhispCore` — pure Swift, no AppKit imports, all state machines are
  testable without a UI.
- `Whisp` — the menu bar app: hotkey monitor, dictation engine, settings,
  HUD.

## Permissions

Whisp asks for three macOS privacy permissions on first launch. All three
are required for the app to work:

| Permission | Why | When prompted |
| --- | --- | --- |
| **Microphone** | Capture audio to transcribe. | Auto, on first start. |
| **Accessibility** | Post Cmd+V or synthetic keystrokes into the focused app. | From the Settings → Permissions tab. macOS opens System Settings → Privacy & Security → Accessibility; toggle Whisp on. |
| **Input Monitoring** | Watch for the Fn+Option hotkey using a CGEventTap. | From the Settings → Permissions tab. macOS opens System Settings → Privacy & Security → Input Monitoring; toggle Whisp on. |

See [docs/permissions.md](docs/permissions.md) for the full TCC story and
what each prompt looks like.

## Install (from a release zip)

1. Download `Whisp-<version>.zip` from
   [GitHub Releases](https://github.com/your-org/whisp/releases).
2. Unzip and drag `Whisp.app` to `/Applications`.
3. **First launch:** right-click `Whisp.app` → **Open** → **Open** (the
   build is unsigned; this is a one-time Gatekeeper acceptance).
4. Whisp lives in the menu bar (the waveform icon). Click it to open
   Settings and grant the three permissions.
5. Press **Fn + Option** anywhere — speak — press **Fn + Option** again to
   stop. Text appears at the cursor.

## Build from source

Whisp depends on the in-tree [Moonshine](https://github.com/moonshine-ai/moonshine)
Swift package. Lay them out as siblings:

```
workspace/
├── moonshine/      # https://github.com/moonshine-ai/moonshine
└── whisp/          # this repo
```

Then:

```bash
cd whisp
./scripts/bootstrap.sh           # builds Moonshine.xcframework once
./scripts/download-models.sh     # ~280 MB medium-streaming-en
swift test                       # unit + integration tests
swift run Whisp                  # launch the menu-bar app (raw executable)
./scripts/build-release.sh       # produce build/Whisp.app and dist/*.zip
./scripts/run-dev.sh             # kill running Whisp, rebuild .app, relaunch
./scripts/run-dev.sh --logs      # same, then tail Console logs
./scripts/run-dev.sh --reset     # also clear TCC grants and re-prompt
```

For day-to-day dev, `./scripts/run-dev.sh` is the one-step rebuild-and-launch
loop. macOS TCC keys permission grants by bundle id **and** code-signing
identity; ad-hoc signatures change per build, so rebuilds may invalidate
your Accessibility / Input Monitoring grants. Toggle Whisp off/on in System
Settings → Privacy & Security to fix (~20 seconds, same workflow VoiceInk
and OpenSuperWhisper use). See [docs/troubleshooting.md](docs/troubleshooting.md).

`bootstrap.sh` invokes Moonshine's `scripts/build-swift.sh` which produces
`moonshine/swift/Moonshine.xcframework` (iOS + Sim + macOS). After that
`swift build` and `swift test` resolve normally.

See [docs/building.md](docs/building.md) for prerequisites
(Xcode 15+, CMake, etc.) and the dev workflow.

## Tests

```bash
swift test                                          # unit + integration
swift test --filter WhispCoreTests                  # fast, no model load
swift test --filter WhispIntegrationTests           # WAV → transcript
```

Three test targets:

- **WhispCoreTests** — pure logic (state machine, transcript buffer,
  hotkey config, insertion modes). Runs in a fraction of a second, used
  in CI on every push.
- **WhispIntegrationTests** — loads Moonshine's bundled `tiny-en` model
  and transcribes a WAV fixture. Confirms the SwiftPM dep resolves, the
  xcframework links, and the transcript shape is what `DictationEngine`
  expects.
- **WhispUITests** — XCUITest skeleton for the Settings window. SwiftPM
  cannot run XCUITests directly; open `Package.swift` in Xcode (or run
  `./scripts/generate-xcodeproj.sh` for guidance) and use the standard
  ⌘U flow.

## Layout

```
whisp/
├── Package.swift
├── Sources/
│   ├── WhispCore/                  # pure logic, no AppKit
│   │   ├── DictationState.swift
│   │   ├── HotkeyConfig.swift
│   │   ├── HotkeyStateMachine.swift
│   │   ├── InsertionMode.swift
│   │   └── TranscriptBuffer.swift
│   └── Whisp/                      # macOS menu-bar app
│       ├── WhispApp.swift          # @main + AppDelegate
│       ├── MenuBarController.swift
│       ├── HotkeyMonitor.swift     # CGEventTap for Fn+Option
│       ├── DictationEngine.swift   # MicTranscriber wrapper
│       ├── TextInjector.swift      # clipboard paste / keystrokes
│       ├── PermissionsManager.swift
│       ├── Settings.swift          # @AppStorage prefs
│       ├── SettingsView.swift      # SwiftUI prefs window
│       ├── ListeningHUD.swift      # floating "listening…" pill
│       └── Resources/
│           ├── Info.plist
│           ├── Whisp.entitlements
│           ├── Assets.xcassets/
│           └── models/             # downloaded by scripts/download-models.sh
├── Tests/
│   ├── WhispCoreTests/
│   ├── WhispIntegrationTests/
│   │   ├── EndToEndTests.swift
│   │   └── Fixtures/beckett.wav
│   └── WhispUITests/
├── scripts/
│   ├── bootstrap.sh                # build Moonshine.xcframework
│   ├── download-models.sh          # fetch STT model
│   ├── build-release.sh            # produce Whisp.app + zip
│   └── generate-xcodeproj.sh
└── docs/
    ├── architecture.md
    ├── building.md
    ├── distribution.md
    ├── permissions.md
    └── roadmap.md
```

## Contributing

PRs welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for the dev
workflow. The codebase is small and well-commented; start at
`Sources/Whisp/WhispApp.swift` and trace outward.

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgements

- [Moonshine](https://moonshine.ai) — the on-device speech-to-text engine
  that makes this possible.
- macOS dictation users who wished the system dictation worked better.
