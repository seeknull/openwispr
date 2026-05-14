# Roadmap

Rough priority order. Issues and PRs welcome on any of these.

## v0.2

- [ ] **Hotkey rebinding** in Settings (currently hard-coded to Fn+Option).
- [ ] **Launch at login** via `SMAppService` (the `launchAtLogin` toggle
      already exists in `Settings.swift` but is not yet wired up).
- [ ] **Press-and-hold mode** as an alternative to toggle.
- [ ] Pin the **model picker** in Settings so users can swap between
      tiny/small/medium without rebuilding the .app.

## v0.3

- [ ] **Notarized builds** + Sparkle auto-update.
- [ ] **Homebrew Cask** for `brew install --cask whisp`.
- [ ] **Multi-language models** — currently we bundle `medium-streaming-en`.

## Stretch

- [ ] **Voice commands** via `IntentRecognizer` ("scratch that" → backspace,
      "new line" → press Enter, "send" → Cmd+Enter).
- [ ] **Diarization** — when more than one voice is detected, only inject
      the registered user's transcript.
- [ ] **Push-to-talk** modifier for accessibility users who find Fn awkward.
