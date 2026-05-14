# Architecture

Whisp is intentionally small. This doc gives the 10-minute tour so you
know what file to open when you want to change something.

## Layers

```
┌──────────────────────────────────────────────────────┐
│  Whisp (executable target)         AppKit / SwiftUI  │
│  ────────────────────────────────  CGEventTap        │
│  WhispApp + AppDelegate            AVFoundation      │
│  MenuBarController                 ApplicationServices│
│  HotkeyMonitor                                       │
│  DictationEngine ──────────────────── MoonshineVoice ┤
│  TextInjector                                        │
│  PermissionsManager                                  │
│  Settings + SettingsView + ListeningHUD              │
├──────────────────────────────────────────────────────┤
│  WhispCore (library target)        Foundation only   │
│  ──────────────────────────────                      │
│  HotkeyStateMachine                                  │
│  TranscriptBuffer                                    │
│  HotkeyConfig                                        │
│  InsertionMode                                       │
│  DictationState                                      │
└──────────────────────────────────────────────────────┘
```

- **WhispCore** is platform-agnostic Foundation code. Everything in it is
  unit-testable without spinning up an event loop, a window server, or
  the Moonshine engine.
- **Whisp** is the AppKit/SwiftUI shell. It calls into MoonshineVoice and
  CoreGraphics.

The cardinal rule: **anything testable belongs in WhispCore.** If you
find yourself reaching for `import AppKit` in WhispCore, the design has
slipped — back out and find another seam.

## Lifetime

1. `@main WhispApp` boots, instantiates `AppDelegate`.
2. `AppDelegate.applicationDidFinishLaunching`:
   - Sets `NSApp` to `.accessory` (menu bar only, no Dock icon).
   - Locates the bundled model (`Resources/models/medium-streaming-en/...`,
     falling back to MoonshineVoice's tiny-en for dev builds).
   - Instantiates `TextInjector`, `DictationEngine`, `HotkeyMonitor`,
     `PermissionsManager`, `MenuBarController`.
   - Starts the CGEventTap.
   - If any permission is missing, opens the Settings window.
3. Each Fn+Option toggle fires through `HotkeyMonitor` →
   `HotkeyStateMachine` → `DictationEngine.start()` or `stop()`.
4. Completed transcript lines from MoonshineVoice flow through
   `TranscriptBuffer` (trims, adds trailing space) and into
   `TextInjector.insert(_:)`.

## State machine

`HotkeyStateMachine` is the canonical source of truth for "are we
currently listening?". `HotkeyMonitor` feeds raw key events to it and
forwards the resulting `Effect` (`.startListening`, `.stopListening`,
or `.none`) to the engine.

Why this split:

- Debounce/repeat-press behavior is policy. Testing it against a real
  CGEventTap is brittle; testing it as a pure function of `(now, held)`
  is one-line.
- The same state machine drives the menu bar's "Stop Dictating" item
  (via `HotkeyMonitor.forceStop()`).

## Insertion strategies

Two modes, picked in Settings:

- **Clipboard paste** (default): save the clipboard, write the transcript
  to it, post Cmd+V, restore the clipboard 120ms later. Works everywhere
  including Electron/web. Fast for long transcripts.
- **Synthesized keystrokes**: post one CGEvent per character via
  `CGEventKeyboardSetUnicodeString`. No clipboard interference; slower
  for long transcripts, sensitive to IME state in some apps.

`TextInjector` is the only place that posts events to other apps. It
requires the Accessibility permission.

## Permissions

`PermissionsManager` queries and prompts for:

- **Microphone** (`AVCaptureDevice.authorizationStatus(for: .audio)`)
- **Accessibility** (`AXIsProcessTrusted` /
  `AXIsProcessTrustedWithOptions`)
- **Input Monitoring** (best-effort: we try creating a listen-only
  CGEventTap; success implies the grant)

See [permissions.md](permissions.md) for the gritty details.

## Concurrency

The app uses Swift 6.1 strict concurrency. The boundary rule:

- `WhispCore` is `Sendable` throughout. Its mutating methods take
  `inout`, never reference shared state.
- App-layer types are `@MainActor`. CGEvent callbacks hop back to
  `MainActor` via `Task { @MainActor in ... }`.

This keeps the threading model boring: everything user-visible is on
the main run loop, audio capture happens on the AVAudioEngine's tap
thread (inside MoonshineVoice), and the event tap fires on its own
run loop thread.

## Why a menu-bar app?

Whisp is global by nature — it has no window of its own when you use
it, because it types into whatever else is focused. A dockless menu-bar
agent matches that mental model and is the right `LSUIElement`/
`NSApp.setActivationPolicy(.accessory)` shape.
