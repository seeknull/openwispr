# Architecture

OpenWispr is intentionally small. This doc gives the 10-minute tour so you
know what file to open when you want to change something.

## Layers

```
┌──────────────────────────────────────────────────────┐
│  OpenWispr (executable target)         AppKit + SwiftUI  │
│  ────────────────────────────────  AVFoundation      │
│  OpenWisprApp + AppDelegate            ApplicationServices│
│  MenuBarController                                   │
│  HotkeyMonitor       (NSEvent global monitor)        │
│  DictationEngine ──────────────────── MoonshineVoice │
│  TextInjector                                        │
│  PermissionsManager                                  │
│  SelfTest                                            │
│  Settings + SettingsView + ListeningHUD              │
├──────────────────────────────────────────────────────┤
│  OpenWisprCore (library target)        Foundation only   │
│  ──────────────────────────────                      │
│  DictationController  ← single source of truth       │
│  HotkeyStateMachine                                  │
│  TranscriptBuffer                                    │
│  HotkeyConfig                                        │
│  InsertionMode                                       │
│  DictationState                                      │
└──────────────────────────────────────────────────────┘
```

- **OpenWisprCore** is platform-agnostic Foundation code. Everything in it
  is unit-testable without spinning up an event loop, a window server,
  or the Moonshine engine.
- **OpenWispr** is the AppKit + SwiftUI shell.

The cardinal rule: **anything testable belongs in OpenWisprCore.** If you
find yourself reaching for `import AppKit` in OpenWisprCore, the design
has slipped — back out and find another seam.

## Lifetime

1. `@main OpenWisprApp` boots, instantiates `AppDelegate`.
2. `AppDelegate.applicationDidFinishLaunching`:
   - Sets `NSApp` to `.accessory` (menu bar only, no Dock icon).
   - Locates the bundled model (`Resources/models/medium-streaming-en/...`,
     falling back to MoonshineVoice's tiny-en for dev builds).
   - Instantiates `TextInjector`, `DictationEngine`, `HotkeyMonitor`,
     `PermissionsManager`, `SelfTest`, `MenuBarController`,
     `DictationController`.
   - Starts the `NSEvent` global+local monitors for the hotkey.
   - Runs `SelfTest` once to drive the initial menu bar icon color.
   - If any permission is missing, opens the Settings window.
3. Each Fn+Option toggle fires through `HotkeyMonitor` →
   `HotkeyStateMachine` → `DictationController.toggle()` and (via
   the same callback) `DictationEngine.start()` / `stop()`.
4. The engine reports state changes back into `DictationController`
   (`engineDidStart`, `engineDidStop`, `engineFailed`). All observers
   (menu bar icon, HUD, hotkey sync) react to the controller's state.
5. Completed transcript lines from MoonshineVoice flow through
   `TranscriptBuffer` (trims, adds trailing space) and into
   `TextInjector.insert(_:)`.

## State

`DictationController` is the single source of truth for the dictation
lifecycle. States are:

- `.idle` — nothing happening.
- `.starting` — toggle received, engine warming up.
- `.listening` — engine is fully running, transcribing.
- `.stopping` — toggle received, engine flushing the final line.
- `.error(message)` — engine failed.

Observers subscribe via `addObserver(_:)` and receive every transition.
Mutations come from `toggle()` (hotkey or menu), `engineDidStart()`,
`engineDidStop()`, `engineFailed(_:)`, `dismissError()`.

`HotkeyStateMachine` is the policy layer that decides whether a given
`flagsChanged` event represents a toggle. It debounces autorepeat and
exposes a `setListening(_:)` so external state changes (menu bar
start, engine error) keep its bookkeeping in sync. Pure function of
`(now, held)` — easy to unit-test.

## Hotkey: NSEvent over CGEventTap

The hotkey monitor uses `NSEvent.addGlobalMonitorForEvents` (plus a
local monitor for when OpenWispr itself has focus) instead of
`CGEventTap`. Two reasons:

1. **Permissions.** `CGEventTap` needs the Input Monitoring TCC grant,
   which macOS 26 silently denies for ad-hoc apps (verified via
   `tccd`'s log). `NSEvent` monitors need Accessibility, which we
   need anyway for keystroke injection. Halves the TCC surface.

2. **Reliability.** `CGEventTap` callbacks are killed by macOS if they
   miss a ~1s deadline. Main-thread SwiftUI work could starve us and
   the tap would get disabled every few seconds. `NSEvent` monitors
   have no such timeout.

Trade-off: NSEvent monitors observe events but can't suppress them.
That's fine for our toggle use case.

## Insertion strategies

Two modes, picked in Settings:

- **Clipboard paste** (default): save the clipboard, write the
  transcript to it, post Cmd+V, restore the clipboard 120ms later.
  Works everywhere including Electron/web. Fast for long transcripts.
- **Synthesized keystrokes**: post one CGEvent per character via
  `CGEventKeyboardSetUnicodeString`. No clipboard interference;
  slower for long transcripts, sensitive to IME state in some apps.

`TextInjector` is the only place that posts events to other apps. It
requires the Accessibility permission.

## Self-test

`SelfTest.run()` performs four cheap checks and aggregates them into
an overall `.ok` / `.warning` / `.failure`:

- Microphone permission
- Accessibility permission
- Speech-to-text model directory present
- Hotkey monitor running

The result drives the menu bar icon color (clean / amber / red) and
appears as a "Status" line in the menu bar dropdown. It runs on
launch, on demand via the menu, and every time the Settings window is
opened.

## Permissions

`PermissionsManager` queries and prompts for two things:

- **Microphone** — `AVCaptureDevice.authorizationStatus(for: .audio)`
- **Accessibility** — `AXIsProcessTrusted` /
  `AXIsProcessTrustedWithOptions`. Required both for keystroke
  injection AND for `NSEvent.addGlobalMonitorForEvents` to deliver
  events.

It also tracks the last CDHash that observed a fully-granted state, so
on launch we can detect "you rebuilt and the grant probably won't
apply" and surface a Hard Reset path.

See [permissions.md](permissions.md) for the gritty TCC details.

## HUD

The "Listening…" floating pill is **pure AppKit** — `NSPanel` +
`NSView` with a `CALayer` background, a `CAShapeLayer` for the pulsing
dot, and an `NSTextField` for the label. An earlier SwiftUI
implementation crashed the app on the second toggle: the
`Circle().animation(.repeatForever)` driver kept poking at a view
whose host window had been ordered out. AppKit + Core Animation has no
such hazard.

## Concurrency

The app uses Swift 6.1 strict concurrency.

- `OpenWisprCore` is `Sendable` throughout. Its mutating methods take
  `inout` and never reference shared state.
- App-layer types are `@MainActor`. NSEvent monitor callbacks run on
  the main run loop; the dispatcher inside `HotkeyMonitor.handle` hops
  to `MainActor` for the engine call.

Audio capture happens on `AVAudioEngine`'s tap thread (inside
MoonshineVoice). The dictation engine marshals completed lines back
to MainActor before invoking the text injector.

## Why a menu-bar app?

OpenWispr is global by nature — it has no window of its own when you use
it, because it types into whatever else is focused. A dockless menu-
bar agent matches that mental model and is the right `LSUIElement` /
`NSApp.setActivationPolicy(.accessory)` shape.
