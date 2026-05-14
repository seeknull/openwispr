# OpenWispr

**Open-source dictation for macOS, powered by [Moonshine](https://moonshine.ai).**

OpenWispr is a tiny menu-bar app that lets you dictate into _any_ macOS app —
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
│  (NSEvent global mon.)  │
└────────────┬────────────┘
             ▼
┌─────────────────────────┐         ┌───────────────────────────┐
│  DictationController    │────────▶│  DictationEngine          │
│  (OpenWisprCore, testable)  │         │  ↳ MicTranscriber         │
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

A `SelfTest` runs on launch and on demand, checking the four things
that have to be healthy for dictation to work. The menu bar icon
reflects the result: clean waveform = healthy, red dot = listening,
red triangle = failure (hover the icon for a tooltip).

Hardened by:

- `OpenWisprCore` — pure Swift, no AppKit imports, all state machines are
  testable without a UI.
- `OpenWispr` — the menu bar app: hotkey monitor, dictation engine, settings,
  HUD, self-test.

## Permissions

OpenWispr asks for **two** macOS privacy permissions on first launch. Both
are required:

| Permission | Why | When prompted |
| --- | --- | --- |
| **Microphone** | Capture audio to transcribe. | From the Settings → Permissions tab. Standard macOS prompt. |
| **Accessibility** | Two things: (1) post Cmd+V or synthetic keystrokes into the focused app, and (2) observe the global Fn+Option hotkey via `NSEvent.addGlobalMonitorForEvents`. | From the Settings → Permissions tab. macOS opens System Settings → Privacy & Security → Accessibility; toggle OpenWispr on, then click **Restart OpenWispr**. |

See [docs/permissions.md](docs/permissions.md) for the full TCC story and
what each prompt looks like.

## Install (from a release zip)

1. Download `OpenWispr-<version>.zip` from
   [GitHub Releases](https://github.com/your-org/openwispr/releases).
2. Unzip and drag `OpenWispr.app` to `/Applications`.
3. **First launch:** right-click `OpenWispr.app` → **Open** → **Open** (the
   build is unsigned; this is a one-time Gatekeeper acceptance).
4. OpenWispr lives in the menu bar (the waveform icon). Click it to open
   Settings and grant the three permissions.
5. Press **Fn + Option** anywhere — speak — press **Fn + Option** again to
   stop. Text appears at the cursor.

## Build from source

OpenWispr depends on the in-tree [Moonshine](https://github.com/moonshine-ai/moonshine)
Swift package. Lay them out as siblings:

```
workspace/
├── moonshine/      # https://github.com/moonshine-ai/moonshine
└── openwispr/          # this repo
```

### One command does the right thing

```bash
cd openwispr
./scripts/run-dev.sh
```

`run-dev.sh` autodetects what's needed:

| If it sees… | It runs… |
| --- | --- |
| `../moonshine/swift/Moonshine.xcframework` missing | `scripts/bootstrap.sh` (builds the framework, ~3 min on Apple Silicon) |
| `Sources/OpenWispr/Resources/models/medium-streaming-en/` missing | Asks before downloading (`scripts/download-models.sh`, ~280 MB) |
| `OpenWispr` already running | Kills it before relaunch |
| Code signature changed from last build | Prints the re-grant nudge (toggle OpenWispr in System Settings → Privacy & Security) |

So **first run** does a full bootstrap + optional model download + build + launch. **Every run after that** just rebuilds incrementally and relaunches.

### Flags

```bash
./scripts/run-dev.sh             # default: bootstrap-if-needed, build, launch
./scripts/run-dev.sh --logs      # also tail Console logs
./scripts/run-dev.sh --no-build  # skip the build, just relaunch
./scripts/run-dev.sh --no-models # don't prompt to download models
./scripts/run-dev.sh --reset     # tccutil reset (re-prompt all permissions)
./scripts/run-dev.sh --clean     # nuke .build/ and build/, full rebuild
```

### Lower-level commands

If you want to run pieces manually instead of via `run-dev.sh`:

```bash
./scripts/bootstrap.sh           # build Moonshine.xcframework
./scripts/download-models.sh     # fetch medium-streaming-en
swift test                       # unit + integration tests
swift run OpenWispr                  # launch raw executable (no .app bundle)
./scripts/build-release.sh       # produce build/OpenWispr.app and dist/*.zip
```

`bootstrap.sh` invokes Moonshine's `scripts/build-swift.sh`, which produces
`moonshine/swift/Moonshine.xcframework` (iOS + Sim + macOS). After that,
`swift build` and `swift test` resolve normally.

### About TCC permissions and rebuilds

macOS TCC keys permission grants by bundle id **and** code-signing identity.
OpenWispr's dev builds use ad-hoc signing, so the signature hash changes per
build and macOS may invalidate your Accessibility grant. The `run-dev.sh`
output flags this when it detects a hash change, and the in-app **Hard
Reset** button (Settings → Permissions) clears everything for re-granting.
See [docs/troubleshooting.md](docs/troubleshooting.md).

See [docs/building.md](docs/building.md) for prerequisites
(Xcode 15+, CMake, etc.) and the dev workflow.

## Tests

```bash
swift test                                          # unit + integration
swift test --filter OpenWisprCoreTests                  # fast, no model load
swift test --filter OpenWisprIntegrationTests           # WAV → transcript
```

Two test targets:

- **OpenWisprCoreTests** — pure logic (state machine, dictation controller,
  transcript buffer, hotkey config, insertion modes, self-test result
  aggregation, HUD lifecycle). Runs in a fraction of a second; CI
  runs this on every push.
- **OpenWisprIntegrationTests** — loads Moonshine's bundled `tiny-en` model
  and transcribes a WAV fixture. Confirms the SwiftPM dep resolves, the
  xcframework links, and the transcript shape is what `DictationEngine`
  expects.

## Layout

```
openwispr/
├── Package.swift
├── Sources/
│   ├── OpenWisprCore/                  # pure logic, no AppKit
│   │   ├── DictationController.swift   # single source of truth state
│   │   ├── DictationState.swift
│   │   ├── HotkeyConfig.swift
│   │   ├── HotkeyStateMachine.swift
│   │   ├── InsertionMode.swift
│   │   └── TranscriptBuffer.swift
│   └── OpenWispr/                      # macOS menu-bar app
│       ├── OpenWisprApp.swift          # @main + AppDelegate
│       ├── MenuBarController.swift
│       ├── HotkeyMonitor.swift     # NSEvent monitor for Fn+Option
│       ├── DictationEngine.swift   # MicTranscriber wrapper
│       ├── TextInjector.swift      # clipboard paste / keystrokes
│       ├── PermissionsManager.swift
│       ├── SelfTest.swift          # launch-time health check
│       ├── Settings.swift          # @AppStorage prefs
│       ├── SettingsView.swift      # SwiftUI prefs window
│       ├── ListeningHUD.swift      # AppKit floating "listening…" pill
│       └── Resources/
│           ├── Info.plist
│           ├── OpenWispr.entitlements
│           ├── Assets.xcassets/
│           └── models/             # downloaded by scripts/download-models.sh
├── Tests/
│   ├── OpenWisprCoreTests/
│   └── OpenWisprIntegrationTests/
│       ├── EndToEndTests.swift
│       └── Fixtures/beckett.wav
├── scripts/
│   ├── bootstrap.sh                # build Moonshine.xcframework
│   ├── download-models.sh          # fetch STT model
│   ├── build-release.sh            # produce OpenWispr.app + zip
│   └── run-dev.sh                  # rebuild + relaunch with autodetect
└── docs/
    ├── architecture.md
    ├── building.md
    ├── distribution.md
    ├── permissions.md
    ├── roadmap.md
    └── troubleshooting.md
```

## Contributing

PRs welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for the dev
workflow. The codebase is small and well-commented; start at
`Sources/OpenWispr/OpenWisprApp.swift` and trace outward.

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgements

- [Moonshine](https://moonshine.ai) — the on-device speech-to-text engine
  that makes this possible.
- macOS dictation users who wished the system dictation worked better.
